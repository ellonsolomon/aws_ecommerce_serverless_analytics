
# S3 Data Lake Bucket
resource "aws_s3_bucket" "data_lake" {
  bucket        = local.bucket_name
  force_destroy = var.environment == "dev" ? true : false

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = var.environment == "prod" ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Fixed aws_s3_bucket_lifecycle_configuration
resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "transition-old-data"
    status = var.environment == "prod" ? "Enabled" : "Disabled"

    # Filter block added
    filter {
      prefix = "" # Apply to all objects
    }

    # could be removed as intelligent tiering is already configured on the optimization
    # start commenting here
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
  # to here

  rule {
    id     = "delete-temp-files"
    status = "Enabled"

    filter {
      prefix = "temp/"
    }

    expiration {
      days = 7
    }
  }
}

# # Create folder structure

resource "aws_s3_object" "folders" {
  for_each = toset([
    "raw-data/",
    "raw-data/orders/",
    "processed-data/",
    "analytics-results/",
    "glue-scripts/",
    "athena-results/",
    "temp/"
  ])

  bucket = aws_s3_bucket.data_lake.id
  key    = each.value

  # Instead of source = "/dev/null", let's use empty content
  content = ""

  # This tells S3 to treat it as a folder
  content_type = "application/x-directory"
}

# Lambda Code Bucket
resource "aws_s3_bucket" "lambda_code" {
  bucket        = local.lambda_bucket
  force_destroy = true

  tags = local.common_tags
}


# DynamoDB Orders Table
resource "aws_dynamodb_table" "orders" {
  name         = "${local.name_prefix}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  attribute {
    name = "customer_id"
    type = "S"
  }

  global_secondary_index {
    name            = "CustomerIdIndex"
    hash_key        = "customer_id"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = var.environment == "prod" ? true : false
  }

  tags = local.common_tags
}

# DynamoDB Customers Table
resource "aws_dynamodb_table" "customers" {
  name         = "${local.name_prefix}-customers"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "customer_id"

  attribute {
    name = "customer_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.environment == "prod" ? true : false
  }

  tags = local.common_tags
}
