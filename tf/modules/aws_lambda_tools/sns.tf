# SNS topic for manual approval notifications
resource "aws_sns_topic" "manual_approval" {
  name = "${var.app}-tools-manual-approval"

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "Manual approval notifications for ${var.app} deployments"
  }
}