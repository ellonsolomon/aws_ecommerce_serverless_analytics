# Schedule automatic data generation every 24 hours
resource "aws_cloudwatch_event_rule" "data_generation_schedule" {
  name        = "${local.name_prefix}-data-gen-schedule"
  description = "Trigger data generation every 24 hours"
  #   "rate(1 day)"
  schedule_expression = "rate(5 minutes)"
  state               = var.environment == "dev" ? "ENABLED" : "DISABLED" # Only in dev
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.data_generation_schedule.name
  target_id = "DataGeneratorTarget"
  arn       = aws_lambda_function.data_generator.arn

  input = jsonencode({
    num_records = 10
  })
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_generator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.data_generation_schedule.arn
}
