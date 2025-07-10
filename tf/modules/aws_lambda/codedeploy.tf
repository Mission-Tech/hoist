# Custom deployment configuration for 25% per minute
resource "aws_codedeploy_deployment_config" "lambda_25_percent_per_minute" {
  deployment_config_name = "${var.app}-${var.env}-25PercentPerMinute"
  compute_platform       = "Lambda"

  traffic_routing_config {
    type = "TimeBasedLinear"

    time_based_linear {
      interval   = 1
      percentage = 100
    }
  }
}

# CodeDeploy application
resource "aws_codedeploy_app" "lambda" {
  name             = "${var.app}-${var.env}"
  compute_platform = "Lambda"

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "CodeDeploy application for ${var.app}-${var.env} Lambda functions"
  }
}

# CodeDeploy deployment group
resource "aws_codedeploy_deployment_group" "lambda" {
  app_name               = aws_codedeploy_app.lambda.name
  deployment_group_name  = "${var.app}-${var.env}"
  service_role_arn      = aws_iam_role.codedeploy.arn
  deployment_config_name = aws_codedeploy_deployment_config.lambda_25_percent_per_minute.deployment_config_name

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  alarm_configuration {
    alarms  = [aws_cloudwatch_metric_alarm.lambda_errors.alarm_name]
    enabled = true
  }

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "CodeDeploy deployment group for ${var.app}-${var.env}"
  }
}
