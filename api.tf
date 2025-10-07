resource "aws_api_gateway_rest_api" "data_ingestion" {
  name        = "${local.name_prefix}-api"
  description = "API for data ingestion"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

resource "aws_api_gateway_resource" "generate" {
  rest_api_id = aws_api_gateway_rest_api.data_ingestion.id
  parent_id   = aws_api_gateway_rest_api.data_ingestion.root_resource_id
  path_part   = "generate"
}

resource "aws_api_gateway_method" "generate_post" {
  rest_api_id   = aws_api_gateway_rest_api.data_ingestion.id
  resource_id   = aws_api_gateway_resource.generate.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.data_ingestion.id
  resource_id = aws_api_gateway_resource.generate.id
  http_method = aws_api_gateway_method.generate_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.data_generator.invoke_arn
}

# Method Response - Required for proper API Gateway configuration
resource "aws_api_gateway_method_response" "generate_200" {
  rest_api_id = aws_api_gateway_rest_api.data_ingestion.id
  resource_id = aws_api_gateway_resource.generate.id
  http_method = aws_api_gateway_method.generate_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

# Integration Response - Links the Lambda response to API Gateway
resource "aws_api_gateway_integration_response" "generate" {
  rest_api_id = aws_api_gateway_rest_api.data_ingestion.id
  resource_id = aws_api_gateway_resource.generate.id
  http_method = aws_api_gateway_method.generate_post.http_method
  status_code = aws_api_gateway_method_response.generate_200.status_code

  depends_on = [
    aws_api_gateway_integration.lambda_integration
  ]
}

# Lambda Permission - Fixed to ensure proper authorization
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_generator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.data_ingestion.execution_arn}/*/*"
}

# Deployment with proper stage and dependencies
resource "aws_api_gateway_deployment" "production" {
  rest_api_id = aws_api_gateway_rest_api.data_ingestion.id

  depends_on = [
    aws_api_gateway_method.generate_post,
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_method_response.generate_200,
    aws_api_gateway_integration_response.generate,
    aws_lambda_permission.api_gateway
  ]

  # Force new deployment when configuration changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.generate.id,
      aws_api_gateway_method.generate_post.id,
      aws_api_gateway_integration.lambda_integration.id,
      aws_api_gateway_method_response.generate_200.id,
      aws_api_gateway_integration_response.generate.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Stage configuration
resource "aws_api_gateway_stage" "api_stage" {
  deployment_id = aws_api_gateway_deployment.production.id
  rest_api_id   = aws_api_gateway_rest_api.data_ingestion.id
  stage_name    = var.environment

  tags = local.common_tags
}

# # Enable CloudWatch Logs for debugging (optional but helpful)
# resource "aws_api_gateway_method_settings" "generate_settings" {
#   rest_api_id = aws_api_gateway_rest_api.data_ingestion.id
#   stage_name  = aws_api_gateway_stage.api_stage.stage_name
#   method_path = "${aws_api_gateway_resource.generate.path_part}/${aws_api_gateway_method.generate_post.http_method}"

#   settings {
#     metrics_enabled    = true
#     logging_level      = "INFO"
#     data_trace_enabled = true
#   }
# }
