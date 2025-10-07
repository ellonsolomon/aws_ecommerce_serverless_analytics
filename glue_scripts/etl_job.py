import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import *
from pyspark.sql.types import *
from awsglue.dynamicframe import DynamicFrame
from datetime import datetime, timedelta

# Get job parameters
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'DATABASE_NAME',
    'S3_BUCKET'
])

# Initialize Spark and Glue contexts
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Set Spark configurations for optimization
spark.conf.set("spark.sql.adaptive.enabled", "true")
spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")
spark.conf.set("spark.sql.adaptive.skewJoin.enabled", "true")

job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Configuration
database_name = args['DATABASE_NAME']
s3_bucket = args['S3_BUCKET']
raw_data_path = f"s3://{s3_bucket}/raw-data/orders/"
processed_data_path = f"s3://{s3_bucket}/processed-data/"
analytics_results_path = f"s3://{s3_bucket}/analytics-results/"

print(f"Starting ETL job: {args['JOB_NAME']}")
print(f"Database: {database_name}")
print(f"S3 Bucket: {s3_bucket}")
print(f"Raw data path: {raw_data_path}")

try:
    # ============================================
    # EXTRACT: Read raw data from S3
    # ============================================

    # Read JSON data with schema inference
    raw_df = spark.read \
        .option("multiline", "false") \
        .option("mode", "PERMISSIVE") \
        .option("columnNameOfCorruptRecord", "_corrupt_record") \
        .json(raw_data_path)

    initial_count = raw_df.count()
    print(f"Read {initial_count} records from raw data")

    if initial_count == 0:
        print("No data to process. Exiting gracefully.")
        job.commit()
        sys.exit(0)

    # Check for corrupt records
    corrupt_count = raw_df.filter(col("_corrupt_record").isNotNull()).count()
    if corrupt_count > 0:
        print(f"Warning: Found {corrupt_count} corrupt records")
        # Log corrupt records for investigation
        raw_df.filter(col("_corrupt_record").isNotNull()) \
            .select("_corrupt_record") \
            .write.mode("append") \
            .text(f"s3://{s3_bucket}/error-logs/corrupt-records/")

    # Filter out corrupt records
    df_valid = raw_df.filter(
        col("_corrupt_record").isNull()).drop("_corrupt_record")

    # ============================================
    # TRANSFORM: Data Quality and Enrichment
    # ============================================

    # Remove duplicates based on order_id
    df_deduped = df_valid.dropDuplicates(['order_id'])
    duplicate_count = df_valid.count() - df_deduped.count()
    if duplicate_count > 0:
        print(f"Removed {duplicate_count} duplicate records")

    # Data quality filters
    df_cleaned = df_deduped.filter(
        (col('order_id').isNotNull()) &
        (col('customer_id').isNotNull()) &
        (col('price').isNotNull()) &
        (col('price') > 0) &
        (col('quantity').isNotNull()) &
        (col('quantity') > 0) &
        (col('total_amount').isNotNull()) &
        (col('total_amount') > 0)
    )

    filtered_count = df_deduped.count() - df_cleaned.count()
    if filtered_count > 0:
        print(f"Filtered out {filtered_count} invalid records")

    # Parse and standardize timestamps
    df_with_timestamp = df_cleaned.withColumn(
        "order_timestamp",
        to_timestamp(col("order_date"))
    ).filter(col("order_timestamp").isNotNull())

    # Add time-based features
    df_time_features = df_with_timestamp \
        .withColumn("order_year", year(col("order_timestamp"))) \
        .withColumn("order_month", month(col("order_timestamp"))) \
        .withColumn("order_day", dayofmonth(col("order_timestamp"))) \
        .withColumn("order_hour", hour(col("order_timestamp"))) \
        .withColumn("order_minute", minute(col("order_timestamp"))) \
        .withColumn("order_weekday", dayofweek(col("order_timestamp"))) \
        .withColumn("order_week", weekofyear(col("order_timestamp"))) \
        .withColumn("order_quarter", quarter(col("order_timestamp")))

    # Add derived features
    df_enriched = df_time_features \
        .withColumn("is_weekend",
                    when(col("order_weekday").isin([1, 7]), lit(True)).otherwise(lit(False))) \
        .withColumn("day_part",
                    when(col("order_hour") < 6, "Night")
                    .when(col("order_hour") < 12, "Morning")
                    .when(col("order_hour") < 18, "Afternoon")
                    .otherwise("Evening")) \
        .withColumn("customer_segment",
                    when(col("customer_age") < 25, "Gen Z")
                    .when(col("customer_age") < 40, "Millennial")
                    .when(col("customer_age") < 55, "Gen X")
                    .when(col("customer_age") < 70, "Boomer")
                    .otherwise("Silent")) \
        .withColumn("order_size_category",
                    when(col("total_amount") < 50, "Small")
                    .when(col("total_amount") < 200, "Medium")
                    .when(col("total_amount") < 500, "Large")
                    .otherwise("Extra Large")) \
        .withColumn("is_high_value",
                    when(col("total_amount") >= 500, lit(True)).otherwise(lit(False))) \
        .withColumn("discount_rate",
                    when(col("discount_percentage").isNotNull(),
                         col("discount_percentage"))
                    .otherwise(lit(0))) \
        .withColumn("actual_discount_amount",
                    when(col("discount_amount").isNotNull(),
                         col("discount_amount"))
                    .otherwise(col("subtotal") * col("discount_rate") / 100)) \
        .withColumn("revenue_per_item",
                    col("total_amount") / col("quantity")) \
        .withColumn("is_discounted",
                    when(col("discount_percentage") > 0, lit(True)).otherwise(lit(False))) \
        .withColumn("processing_timestamp", current_timestamp()) \
        .withColumn("etl_batch_id", lit(args['JOB_NAME'] + "_" + datetime.now().strftime("%Y%m%d_%H%M%S")))

    # Ensure data types are correct
    df_typed = df_enriched \
        .withColumn("price", col("price").cast(DoubleType())) \
        .withColumn("quantity", col("quantity").cast(IntegerType())) \
        .withColumn("total_amount", col("total_amount").cast(DoubleType())) \
        .withColumn("subtotal", col("subtotal").cast(DoubleType())) \
        .withColumn("discount_amount", col("discount_amount").cast(DoubleType())) \
        .withColumn("customer_age", col("customer_age").cast(IntegerType()))

    # Select final columns in order
    final_columns = [
        # Order Information
        "order_id",
        "order_timestamp",
        "order_year",
        "order_month",
        "order_day",
        "order_hour",
        "order_weekday",
        "order_week",
        "order_quarter",
        "is_weekend",
        "day_part",

        # Customer Information
        "customer_id",
        "customer_age",
        "customer_location",
        "customer_segment",
        "is_returning_customer",
        "is_prime_member",

        # Product Information
        "product_name",
        "category",
        "quantity",
        "price",
        "revenue_per_item",

        # Financial Information
        "subtotal",
        "discount_percentage",
        "discount_amount",
        "total_amount",
        "is_discounted",
        "order_size_category",
        "is_high_value",

        # Transaction Details
        "payment_method",
        "shipping_method",
        "device_type",
        "referral_source",
        "promo_code_used",
        "estimated_delivery_days",

        # Session Information
        "session_duration_seconds",
        "items_viewed",

        # Processing Metadata
        "processing_timestamp",
        "etl_batch_id"
    ]

    # Select only columns that exist
    existing_columns = [
        col for col in final_columns if col in df_typed.columns]
    df_final = df_typed.select(existing_columns)

    print(
        f"Final dataset: {df_final.count()} records, {len(df_final.columns)} columns")

    # ============================================
    # LOAD: Write processed data
    # ============================================

    # Write main processed data with partitioning
    df_final.repartition("order_year", "order_month") \
        .write \
        .mode("append") \
        .partitionBy("order_year", "order_month", "order_day") \
        .parquet(processed_data_path)

    print(f"Successfully wrote processed data to {processed_data_path}")

    # ============================================
    # ANALYTICS: Generate aggregated tables
    # ============================================

    print("Generating analytics summaries...")

    # 1. Daily Revenue Summary
    daily_summary = df_final.groupBy(
        "order_year", "order_month", "order_day", "order_weekday", "is_weekend"
    ).agg(
        count("order_id").alias("total_orders"),
        countDistinct("customer_id").alias("unique_customers"),
        sum("total_amount").alias("total_revenue"),
        avg("total_amount").alias("avg_order_value"),
        max("total_amount").alias("max_order_value"),
        min("total_amount").alias("min_order_value"),
        sum("quantity").alias("total_items_sold"),
        avg("discount_percentage").alias("avg_discount_rate"),
        sum(when(col("is_discounted"), 1).otherwise(
            0)).alias("discounted_orders"),
        sum(when(col("is_high_value"), 1).otherwise(
            0)).alias("high_value_orders"),
        sum(when(col("is_prime_member"), 1).otherwise(0)).alias("prime_orders")
    ).withColumn("conversion_rate",
                 col("total_orders") / col("unique_customers")
                 ).orderBy("order_year", "order_month", "order_day")

    daily_summary.coalesce(1).write \
        .mode("overwrite") \
        .option("header", "true") \
        .parquet(f"{analytics_results_path}daily_summary/")

    # 2. Product Performance
    product_performance = df_final.groupBy("product_name", "category").agg(
        count("order_id").alias("order_count"),
        sum("quantity").alias("total_quantity"),
        sum("total_amount").alias("total_revenue"),
        avg("total_amount").alias("avg_order_value"),
        avg("discount_percentage").alias("avg_discount"),
        countDistinct("customer_id").alias("unique_buyers"),
        avg("revenue_per_item").alias("avg_item_price")
    ).withColumn("revenue_rank",
                 dense_rank().over(Window.orderBy(desc("total_revenue")))
                 ).orderBy(desc("total_revenue"))

    product_performance.coalesce(1).write \
        .mode("overwrite") \
        .option("header", "true") \
        .parquet(f"{analytics_results_path}product_performance/")

    # 3. Customer Segment Analysis
    customer_segments = df_final.groupBy(
        "customer_segment", "customer_location", "is_prime_member"
    ).agg(
        countDistinct("customer_id").alias("unique_customers"),
        count("order_id").alias("total_orders"),
        sum("total_amount").alias("total_revenue"),
        avg("total_amount").alias("avg_order_value"),
        avg("customer_age").alias("avg_age"),
        sum("quantity").alias("total_items"),
        avg("items_viewed").alias("avg_items_viewed"),
        avg("session_duration_seconds").alias("avg_session_duration")
    ).withColumn("orders_per_customer",
                 col("total_orders") / col("unique_customers")
                 ).orderBy(desc("total_revenue"))

    customer_segments.coalesce(1).write \
        .mode("overwrite") \
        .option("header", "true") \
        .parquet(f"{analytics_results_path}customer_segments/")

    # 4. Payment & Device Analysis
    payment_device = df_final.groupBy("payment_method", "device_type").agg(
        count("order_id").alias("transaction_count"),
        sum("total_amount").alias("total_revenue"),
        avg("total_amount").alias("avg_transaction_value"),
        countDistinct("customer_id").alias("unique_users")
    ).orderBy(desc("transaction_count"))

    payment_device.coalesce(1).write \
        .mode("overwrite") \
        .option("header", "true") \
        .parquet(f"{analytics_results_path}payment_device_analysis/")

    # 5. Hourly Patterns
    hourly_patterns = df_final.groupBy("order_hour", "day_part").agg(
        count("order_id").alias("order_count"),
        sum("total_amount").alias("total_revenue"),
        avg("total_amount").alias("avg_order_value"),
        countDistinct("customer_id").alias("unique_customers")
    ).orderBy("order_hour")

    hourly_patterns.coalesce(1).write \
        .mode("overwrite") \
        .option("header", "true") \
        .parquet(f"{analytics_results_path}hourly_patterns/")

    print("Analytics summaries generated successfully")

    # ============================================
    # DATA CATALOG: Update Glue Catalog
    # ============================================

    # Convert to DynamicFrame for Glue Catalog
    dynamic_frame = DynamicFrame.fromDF(
        df_final, glueContext, "processed_orders")

    # Write to Glue Catalog (this creates/updates the table in the catalog)
    sink = glueContext.write_dynamic_frame.from_catalog(
        frame=dynamic_frame,
        database=database_name,
        table_name="processed_orders",
        additional_options={
            "enableUpdateCatalog": True,
            "updateBehavior": "UPDATE_IN_DATABASE"
        }
    )

    print("Glue catalog updated successfully")

    # ============================================
    # JOB METRICS: Log performance metrics
    # ============================================

    job_metrics = {
        "job_name": args['JOB_NAME'],
        "start_time": job.get_start_time(),
        "raw_records": initial_count,
        "processed_records": df_final.count(),
        "corrupt_records": corrupt_count,
        "duplicate_records": duplicate_count,
        "filtered_records": filtered_count,
        "unique_customers": df_final.select("customer_id").distinct().count(),
        "unique_products": df_final.select("product_name").distinct().count(),
        "total_revenue": df_final.agg(sum("total_amount")).collect()[0][0],
        "processing_date": datetime.now().isoformat()
    }

    print(f"Job metrics: {job_metrics}")

    # Write metrics to S3 for monitoring
    metrics_df = spark.createDataFrame([job_metrics])
    metrics_df.coalesce(1).write \
        .mode("append") \
        .json(f"s3://{s3_bucket}/job-metrics/")

except Exception as e:
    print(f"Error in ETL job: {str(e)}")
    import traceback
    traceback.print_exc()
    raise e
finally:
    # Commit the job
    job.commit()
    print(f"ETL job {args['JOB_NAME']} completed")
