# Basic error rate alarm for Lambda function
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.app}-${var.env}-lambda-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = var.error_rate_threshold
  alarm_description   = "This metric monitors Lambda function error rate"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.main.function_name
  }

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Error rate alarm for ${var.app}-${var.env} Lambda function"
  }
}