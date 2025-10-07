import json
import boto3
import base64
from datetime import datetime
import os
from decimal import Decimal


def lambda_handler(event, context):
    """
    Lambda function to process Kinesis stream records and store in S3 and DynamoDB
    """
    # Initialize AWS services
    s3 = boto3.client('s3')
    dynamodb = boto3.resource('dynamodb')

    # Get environment variables
    bucket_name = os.environ['S3_BUCKET']
    orders_table_name = os.environ['DYNAMODB_ORDERS_TABLE']

    orders_table = dynamodb.Table(orders_table_name)

    processed_records = 0
    failed_records = []
    batch_records = []

    print(f"Processing {len(event.get('Records', []))} records from Kinesis")

    # Process each record from Kinesis
    for record in event.get('Records', []):
        try:
            # Decode the Kinesis data
            payload = json.loads(
                base64.b64decode(record['kinesis']['data']).decode('utf-8')
            )

            # Add processing metadata
            payload['processed_timestamp'] = datetime.now().isoformat()
            payload['kinesis_sequence_number'] = record['kinesis']['sequenceNumber']
            payload['kinesis_partition_key'] = record['kinesis']['partitionKey']

            # Determine customer segment based on age
            if payload.get('customer_age', 0) < 25:
                payload['customer_segment'] = 'Gen Z'
            elif payload['customer_age'] < 40:
                payload['customer_segment'] = 'Millennial'
            elif payload['customer_age'] < 55:
                payload['customer_segment'] = 'Gen X'
            else:
                payload['customer_segment'] = 'Boomer'

            # Add date partitioning fields
            try:
                order_date = datetime.fromisoformat(
                    payload['order_date'].replace('Z', '+00:00'))
            except:
                order_date = datetime.now()

            payload['order_year'] = order_date.year
            payload['order_month'] = order_date.month
            payload['order_day'] = order_date.day
            payload['order_hour'] = order_date.hour
            payload['order_weekday'] = order_date.weekday()

            # Add derived metrics
            payload['is_weekend'] = payload['order_weekday'] >= 5
            payload['is_high_value'] = payload.get('total_amount', 0) > 500

            # Categorize order size
            total_amount = payload.get('total_amount', 0)
            if total_amount < 50:
                payload['order_size'] = 'Small'
            elif total_amount < 200:
                payload['order_size'] = 'Medium'
            elif total_amount < 500:
                payload['order_size'] = 'Large'
            else:
                payload['order_size'] = 'Extra Large'

            # Store in DynamoDB for real-time queries
            try:
                # Convert float to Decimal for DynamoDB
                dynamodb_payload = json.loads(
                    json.dumps(payload), parse_float=Decimal)
                orders_table.put_item(Item=dynamodb_payload)
                print(f"Stored order {payload['order_id']} in DynamoDB")
            except Exception as e:
                print(f"Error storing in DynamoDB: {str(e)}")

            # Add to batch for S3 storage
            batch_records.append(payload)
            processed_records += 1

        except Exception as e:
            error_msg = f"Error processing record: {str(e)}"
            print(error_msg)
            failed_records.append({
                'sequenceNumber': record.get('kinesis', {}).get('sequenceNumber', 'unknown'),
                'error': error_msg
            })

    # Batch write to S3
    if batch_records:
        try:
            # Group records by date for partitioning
            partitioned_data = {}
            for record in batch_records:
                date_key = f"{record['order_year']}/{record['order_month']:02d}/{record['order_day']:02d}"
                if date_key not in partitioned_data:
                    partitioned_data[date_key] = []
                partitioned_data[date_key].append(record)

            # Write each partition to S3
            for date_partition, records in partitioned_data.items():
                # Create a unique file name using timestamp
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S_%f')

                # Write raw data
                raw_key = f"raw-data/orders/{date_partition}/batch_{timestamp}.json"
                s3.put_object(
                    Bucket=bucket_name,
                    Key=raw_key,
                    Body=json.dumps(records, default=str),
                    ContentType='application/json'
                )
                print(f"Wrote {len(records)} records to S3: {raw_key}")

                # Write processed data in newline-delimited JSON for better Athena compatibility
                processed_key = f"processed-data/orders/{date_partition}/batch_{timestamp}.jsonl"
                jsonl_content = '\n'.join(
                    [json.dumps(r, default=str) for r in records])
                s3.put_object(
                    Bucket=bucket_name,
                    Key=processed_key,
                    Body=jsonl_content,
                    ContentType='application/x-ndjson'
                )

        except Exception as e:
            print(f"Error writing to S3: {str(e)}")

    # Log processing results
    result = {
        'processed_records': processed_records,
        'failed_records': len(failed_records),
        'total_records': len(event.get('Records', [])),
        'timestamp': datetime.now().isoformat()
    }

    print(f"Processing complete: {json.dumps(result)}")

    # Return batch item failures for retry
    response = {
        'statusCode': 200 if processed_records > 0 else 500,
        'result': result
    }

    # Add batch item failures for Kinesis retry mechanism
    if failed_records:
        response['batchItemFailures'] = [
            {'itemIdentifier': r['sequenceNumber']} for r in failed_records
        ]

    return response
