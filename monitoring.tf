# ========================================
# CloudWatch Monitoring Resources
# ========================================

# Log Groups
resource "aws_cloudwatch_log_group" "lambda_data_generator" {
  name              = "/aws/lambda/${aws_lambda_function.data_generator.function_name}"
  retention_in_days = local.log_retention

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_stream_processor" {
  name              = "/aws/lambda/${aws_lambda_function.stream_processor.function_name}"
  retention_in_days = local.log_retention

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "glue_job" {
  name              = "/aws-glue/jobs/${aws_glue_job.etl_job.name}"
  retention_in_days = local.log_retention

  tags = local.common_tags
}

# ========================================
# CloudWatch Alarms
# ========================================

# Lambda Data Generator Errors
resource "aws_cloudwatch_metric_alarm" "lambda_generator_errors" {
  alarm_name          = "${local.name_prefix}-generator-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Lambda data generator error rate too high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.data_generator.function_name
  }

  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts.arn] : []

  tags = local.common_tags
}

# Lambda Stream Processor Errors
resource "aws_cloudwatch_metric_alarm" "lambda_processor_errors" {
  alarm_name          = "${local.name_prefix}-processor-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Lambda stream processor error rate too high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.stream_processor.function_name
  }

  alarm_actions = var.alert_email != "" ? [aws_sns_topic.alerts.arn] : []

  tags = local.common_tags
}

# Lambda Concurrent Executions
resource "aws_cloudwatch_metric_alarm" "lambda_concurrent_executions" {
  alarm_name          = "${local.name_prefix}-lambda-concurrent-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ConcurrentExecutions"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "900"
  alarm_description   = "Lambda concurrent executions approaching limit"

  dimensions = {
    FunctionName = aws_lambda_function.stream_processor.function_name
  }

  tags = local.common_tags
}

# Kinesis Stream Records Behind
resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  alarm_name          = "${local.name_prefix}-kinesis-iterator-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "60000" # 1 minute behind
  alarm_description   = "Kinesis stream processing is falling behind"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.data_stream.name
  }

  tags = local.common_tags
}

# Kinesis Throttling
resource "aws_cloudwatch_metric_alarm" "kinesis_throttles" {
  alarm_name          = "${local.name_prefix}-kinesis-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UserRecordsPending"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000"
  alarm_description   = "Kinesis stream is throttling"

  dimensions = {
    StreamName = aws_kinesis_stream.data_stream.name
  }

  tags = local.common_tags
}

# DynamoDB Throttles
resource "aws_cloudwatch_metric_alarm" "dynamodb_throttles" {
  alarm_name          = "${local.name_prefix}-dynamodb-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "DynamoDB throttling detected"

  dimensions = {
    TableName = aws_dynamodb_table.orders.name
  }

  tags = local.common_tags
}

# S3 4xx Errors
resource "aws_cloudwatch_metric_alarm" "s3_4xx_errors" {
  alarm_name          = "${local.name_prefix}-s3-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xxErrors"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Sum"
  threshold           = "50"
  alarm_description   = "S3 bucket experiencing high 4xx errors"

  dimensions = {
    BucketName = aws_s3_bucket.data_lake.id
  }

  tags = local.common_tags
}

# Glue Job Failures
resource "aws_cloudwatch_metric_alarm" "glue_job_failures" {
  alarm_name          = "${local.name_prefix}-glue-job-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "glue.driver.aggregate.numFailedTasks"
  namespace           = "AWS/Glue"
  period              = "3600"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Glue ETL job has failed"
  treat_missing_data  = "notBreaching"

  dimensions = {
    JobName  = aws_glue_job.etl_job.name
    JobRunId = "ALL"
  }

  tags = local.common_tags
}

# API Gateway 4XX Errors
resource "aws_cloudwatch_metric_alarm" "api_4xx_errors" {
  alarm_name          = "${local.name_prefix}-api-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "100"
  alarm_description   = "API Gateway high 4XX error rate"

  dimensions = {
    ApiName = aws_api_gateway_rest_api.data_ingestion.name
    Stage   = aws_api_gateway_stage.api_stage.stage_name
  }

  tags = local.common_tags
}

# ========================================
# SNS Topic for Alerts
# ========================================

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"

  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "alert_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ========================================
# CloudWatch Dashboard
# ========================================

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: Overview Metrics
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 6
        height = 6
        properties = {
          title = "API Gateway Requests"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", aws_api_gateway_rest_api.data_ingestion.name, "Stage", var.environment, { stat = "Sum", label = "Total Requests" }],
            [".", "4XXError", ".", ".", ".", ".", { stat = "Sum", label = "4XX Errors", color = "#ff9900" }],
            [".", "5XXError", ".", ".", ".", ".", { stat = "Sum", label = "5XX Errors", color = "#d13212" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 0
        width  = 6
        height = 6
        properties = {
          title = "Lambda Functions Performance"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.data_generator.function_name, { stat = "Sum", label = "Data Generator" }],
            [".", "Invocations", ".", aws_lambda_function.stream_processor.function_name, { stat = "Sum", label = "Stream Processor" }],
            [".", "Errors", ".", aws_lambda_function.data_generator.function_name, { stat = "Sum", label = "Generator Errors", color = "#d13212" }],
            [".", "Errors", ".", aws_lambda_function.stream_processor.function_name, { stat = "Sum", label = "Processor Errors", color = "#ff9900" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 6
        height = 6
        properties = {
          title = "Kinesis Stream Metrics"
          metrics = [
            ["AWS/Kinesis", "IncomingRecords", "StreamName", aws_kinesis_stream.data_stream.name, { stat = "Sum" }],
            [".", "IncomingBytes", ".", ".", { stat = "Sum" }],
            [".", "GetRecords.IteratorAgeMilliseconds", ".", ".", { stat = "Maximum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 18
        y      = 0
        width  = 6
        height = 6
        properties = {
          title = "Lambda Duration"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", aws_lambda_function.data_generator.function_name, { stat = "Average" }],
            [".", "Duration", ".", aws_lambda_function.stream_processor.function_name, { stat = "Average" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
          yAxis = {
            left = {
              label = "milliseconds"
            }
          }
        }
      },
      # Row 2: Storage Metrics
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          title = "DynamoDB Performance"
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", aws_dynamodb_table.orders.name, { stat = "Sum" }],
            [".", "ConsumedWriteCapacityUnits", ".", ".", { stat = "Sum" }],
            [".", "UserErrors", ".", ".", { stat = "Sum", color = "#d13212" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          title = "S3 Request Metrics"
          metrics = [
            ["AWS/S3", "AllRequests", "BucketName", aws_s3_bucket.data_lake.id, { stat = "Sum" }],
            [".", "GetRequests", ".", ".", { stat = "Sum" }],
            [".", "PutRequests", ".", ".", { stat = "Sum" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          title = "Glue Job Metrics"
          metrics = [
            ["AWS/Glue", "glue.driver.aggregate.numCompletedTasks", "JobName", aws_glue_job.etl_job.name, "JobRunId", "ALL", { stat = "Sum" }],
            [".", "glue.driver.aggregate.numFailedTasks", ".", ".", ".", ".", { stat = "Sum", color = "#d13212" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 3600
        }
      },
      # Row 3: System Health
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title = "System Health Overview"
          metrics = [
            ["AWS/Lambda", "ConcurrentExecutions", { stat = "Maximum" }],
            [".", "Throttles", { stat = "Sum", color = "#ff9900" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          period  = 60
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Recent Errors"
          query  = "SOURCE '${aws_cloudwatch_log_group.lambda_stream_processor.name}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
          region = var.aws_region
        }
      }
    ]
  })
}

# ========================================
# Outputs
# ========================================

output "dashboard_url" {
  description = "CloudWatch Dashboard URL"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "sns_topic_arn" {
  description = "SNS Topic ARN for alerts"
  value       = aws_sns_topic.alerts.arn
}
