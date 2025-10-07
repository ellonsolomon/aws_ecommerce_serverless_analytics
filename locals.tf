locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    # CreatedAt   = formatdate("YYYY-MM-DD", timestamp())
  }

  # Naming conventions - using random suffix for uniqueness
  bucket_name   = "${var.project_name}-datalake-${var.environment}-${random_string.suffix.result}"
  lambda_bucket = "${var.project_name}-lambda-${var.environment}-${random_string.suffix.result}"
  glue_db_name  = replace("${var.project_name}_db_${var.environment}_${random_string.suffix.result}", "-", "_")
  name_prefix   = "${var.project_name}-${var.environment}"

  # Environment-specific settings
  kinesis_shards = var.environment == "prod" ? 2 : 1
  lambda_memory  = var.environment == "prod" ? 512 : 256
  log_retention  = var.environment == "prod" ? 30 : 7
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false

  # Keepers ensure the random string regenerates if these values change
  keepers = {
    project_name = var.project_name
    environment  = var.environment
  }
}
