# Glue Catalog Database
resource "aws_glue_catalog_database" "analytics_db" {
  name        = local.glue_db_name
  description = "Analytics database for ${var.project_name}"

  tags = local.common_tags
}

# Upload Glue Script to S3
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.data_lake.id
  key    = "glue-scripts/etl_job.py"
  source = "${path.module}/glue_scripts/etl_job.py"
  etag   = filemd5("${path.module}/glue_scripts/etl_job.py")
}

# Glue Crawler
resource "aws_glue_crawler" "s3_crawler" {
  database_name = aws_glue_catalog_database.analytics_db.name
  name          = "${local.name_prefix}-crawler"
  role          = aws_iam_role.glue_service.arn

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.id}/raw-data/"
  }

  s3_target {
    path = "s3://${aws_s3_bucket.data_lake.id}/processed-data/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  tags = local.common_tags
}

# Glue ETL Job
resource "aws_glue_job" "etl_job" {
  name     = "${local.name_prefix}-etl-job"
  role_arn = aws_iam_role.glue_service.arn

  command {
    script_location = "s3://${aws_s3_bucket.data_lake.id}/glue-scripts/etl_job.py"
    python_version  = "3"
  }

  default_arguments = {
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--job-language"                     = "python"
    "--TempDir"                          = "s3://${aws_s3_bucket.data_lake.id}/temp/"
    "--DATABASE_NAME"                    = aws_glue_catalog_database.analytics_db.name
    "--S3_BUCKET"                        = aws_s3_bucket.data_lake.id
  }

  max_retries       = 1
  timeout           = 60
  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = var.environment == "prod" ? 3 : 2

  execution_property {
    max_concurrent_runs = 1
  }

  tags = local.common_tags
}

# Athena Workgroup
resource "aws_athena_workgroup" "analytics" {
  name = "${local.name_prefix}-workgroup"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.data_lake.id}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = local.common_tags
}


# Schedule crawler to run every hour
resource "aws_glue_trigger" "crawler_schedule" {
  name     = "${local.name_prefix}-crawler-trigger"
  type     = "SCHEDULED"
  schedule = "cron(0 * * * ? *)" # Every hour
  # Alternative schedules:
  # schedule = "cron(0 0/6 * * ? *)"  # Every 6 hours
  # schedule = "cron(0 0 * * ? *)"     # Daily at midnight

  actions {
    crawler_name = aws_glue_crawler.s3_crawler.name
  }

  tags = local.common_tags
}
