
# # Lambda reserved concurrency (performance tuning) , could be run on creation 
# resource "aws_lambda_provisioned_concurrency_config" "data_generator" {
#   function_name                     = aws_lambda_function.data_generator.function_name
#   provisioned_concurrent_executions = var.environment == "prod" ? 5 : 0
#   qualifier                         = aws_lambda_function.data_generator.version
# }

# S3 Intelligent Tiering (cost optimization)
resource "aws_s3_bucket_intelligent_tiering_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  name   = "EntireBucket"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}

# Budget alerts
resource "aws_budgets_budget" "monthly" {
  name         = "${local.name_prefix}-monthly-budget"
  budget_type  = "COST"
  limit_amount = "100"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }
}
