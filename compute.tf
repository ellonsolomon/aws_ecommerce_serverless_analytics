# Data Generator Lambda
data "archive_file" "data_generator" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/data_generator.zip"

  source {
    content  = file("${path.module}/lambda_functions/data_generator.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "data_generator" {
  filename         = data.archive_file.data_generator.output_path
  function_name    = "${local.name_prefix}-data-generator"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.data_generator.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = local.lambda_memory

  environment {
    variables = {
      KINESIS_STREAM_NAME      = aws_kinesis_stream.data_stream.name
      DYNAMODB_ORDERS_TABLE    = aws_dynamodb_table.orders.name
      DYNAMODB_CUSTOMERS_TABLE = aws_dynamodb_table.customers.name
    }
  }

  tags = local.common_tags
}


# newly added for streaming setup

# Stream Processor Lambda
data "archive_file" "stream_processor" {
  type        = "zip"
  output_path = "${path.module}/lambda_packages/stream_processor.zip"

  source {
    content  = file("${path.module}/lambda_functions/stream_processor.py")
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "stream_processor" {
  filename         = data.archive_file.stream_processor.output_path
  function_name    = "${local.name_prefix}-stream-processor"
  role             = aws_iam_role.lambda_execution.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.stream_processor.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = local.lambda_memory * 2 # Needs more memory for processing

  environment {
    variables = {
      S3_BUCKET             = aws_s3_bucket.data_lake.id
      DYNAMODB_ORDERS_TABLE = aws_dynamodb_table.orders.name
    }
  }

  tags = local.common_tags
}

# Kinesis Event Source Mapping
resource "aws_lambda_event_source_mapping" "kinesis_lambda" {
  event_source_arn                   = aws_kinesis_stream.data_stream.arn
  function_name                      = aws_lambda_function.stream_processor.arn
  starting_position                  = "LATEST"
  batch_size                         = 100
  maximum_batching_window_in_seconds = 5

  depends_on = [
    aws_iam_role_policy.lambda_policy,
    aws_iam_role_policy_attachment.lambda_kinesis
  ]
}
