# Custom deployment configuration for 25% per minute
resource "aws_codedeploy_deployment_config" "lambda_deployment_config" {
  deployment_config_name = "${var.app}-${var.env}"
  compute_platform       = "Lambda"

    traffic_routing_config {
        type = "TimeBasedCanary"

        # NOTE(izaak): what I think i'd like ideally is a two-minute window after the 100% traffic shift
        # where, if cloudwatch alarms saw something (like an error spike) we'd do an automated rollback.
        # That doesn't seem possible, and this below is the next best thing.
        time_based_canary {
            percentage = 99   # first step = 99 % of requests
            interval   = 5    # wait 5 minutes, then CodeDeploy shifts the last 1 %
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
  deployment_config_name = aws_codedeploy_deployment_config.lambda_deployment_config.deployment_config_name

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
