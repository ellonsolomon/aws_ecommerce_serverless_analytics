output "api_endpoint" {
  description = "API Gateway endpoint URL"
  value       = "https://${aws_api_gateway_rest_api.data_ingestion.id}.execute-api.${var.aws_region}.amazonaws.com/${var.environment}/generate"
}
output "s3_bucket" {
  description = "S3 data lake bucket name"
  value       = aws_s3_bucket.data_lake.id
}

output "kinesis_stream" {
  description = "Kinesis stream name"
  value       = aws_kinesis_stream.data_stream.name
}

output "dynamodb_tables" {
  description = "DynamoDB table names"
  value = {
    orders    = aws_dynamodb_table.orders.name
    customers = aws_dynamodb_table.customers.name
  }
}

output "glue_database" {
  description = "Glue catalog database name"
  value       = aws_glue_catalog_database.analytics_db.name
}

output "athena_workgroup" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.analytics.name
}

# output "dashboard_url" {
#   description = "CloudWatch Dashboard URL"
#   value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
# }

output "quicksight_instructions" {
  description = "QuickSight setup instructions"
  value       = <<-EOT
    To set up QuickSight:
    1. Go to QuickSight console
    2. Create new Athena data source
    3. Select database: ${aws_glue_catalog_database.analytics_db.name}
    4. Use workgroup: ${aws_athena_workgroup.analytics.name}
  EOT
}
