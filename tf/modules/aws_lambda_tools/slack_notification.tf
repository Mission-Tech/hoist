# Check if Slack CD webhook exists in Parameter Store
data "aws_ssm_parameter" "slack_cd_webhook" {
  count = 1
  name  = "/coreinfra/shared/slack_cd_webhook_url"
  
  # Continue even if parameter doesn't exist
  lifecycle {
    postcondition {
      condition     = can(self.value)
      error_message = "Slack CD webhook not found - notifications will be disabled"
    }
  }
}

locals {
  # Only enable Slack notifications if webhook exists
  slack_notifications_enabled = try(data.aws_ssm_parameter.slack_cd_webhook[0].value != "", false)
  slack_notification_lambda_name = "${var.app}-tools-slack-cd-notification"
}

# IAM role for Slack notification Lambda
resource "aws_iam_role" "slack_notification_lambda" {
  count = local.slack_notifications_enabled ? 1 : 0
  name  = local.slack_notification_lambda_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "Role for Slack notification Lambda"
  }
}

# Policy for Slack notification Lambda
resource "aws_iam_role_policy" "slack_notification_lambda" {
  count = local.slack_notifications_enabled ? 1 : 0
  name  = local.slack_notification_lambda_name
  role  = aws_iam_role.slack_notification_lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${local.region}:${local.tools_account_id}:log-group:/aws/lambda/${local.slack_notification_lambda_name}",
          "arn:aws:logs:${local.region}:${local.tools_account_id}:log-group:/aws/lambda/${local.slack_notification_lambda_name}:*"
        ]
      }
    ]
  })
}

# Archive the Lambda function
data "archive_file" "slack_notification_lambda" {
  count       = local.slack_notifications_enabled ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/slack_notification_lambda.zip"
  
  source {
    content  = file("${path.module}/slack_notification_lambda/index.py")
    filename = "index.py"
  }
}

# Lambda function for Slack notifications
resource "aws_lambda_function" "slack_notification" {
  count            = local.slack_notifications_enabled ? 1 : 0
  filename         = data.archive_file.slack_notification_lambda[0].output_path
  function_name    = local.slack_notification_lambda_name
  role            = aws_iam_role.slack_notification_lambda[0].arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 30
  source_code_hash = data.archive_file.slack_notification_lambda[0].output_base64sha256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = nonsensitive(data.aws_ssm_parameter.slack_cd_webhook[0].value)
    }
  }

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "Sends manual approval notifications to Slack"
  }
}

# Permission for SNS to invoke Lambda
resource "aws_lambda_permission" "sns_invoke_slack" {
  count         = local.slack_notifications_enabled ? 1 : 0
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notification[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.manual_approval.arn
}

# Subscribe Lambda to SNS topic
resource "aws_sns_topic_subscription" "slack_notification" {
  count     = local.slack_notifications_enabled ? 1 : 0
  topic_arn = aws_sns_topic.manual_approval.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notification[0].arn
}