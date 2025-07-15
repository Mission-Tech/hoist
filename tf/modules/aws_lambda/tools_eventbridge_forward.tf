# Forward ECR push events to tools account

# IAM role for EventBridge to send events to tools account
resource "aws_iam_role" "eventbridge_cross_account" {
  name = "${var.app}-${var.env}-eventbridge-tools"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "EventBridge role for cross-account event forwarding to tools account"
  }
}

# Policy for EventBridge to put events to tools account
resource "aws_iam_role_policy" "eventbridge_cross_account" {
  name = "${var.app}-${var.env}-eventbridge-tools"
  role = aws_iam_role.eventbridge_cross_account.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:PutEvents"
        ]
        Resource = [
          "arn:aws:events:${data.aws_region.current.name}:${local.tools_account_id}:event-bus/default"
        ]
      }
    ]
  })
}

# EventBridge rule to forward ECR push events to tools account
resource "aws_cloudwatch_event_rule" "ecr_push_forward" {
  name        = "${var.app}-${var.env}-ecr-push-forward"
  description = "Forward ECR image PUSH to Tools account"

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Action"]
    detail = {
      action-type     = ["PUSH"]
      repository-name = [aws_ecr_repository.lambda_repository.name]
    }
  })

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Forward ECR push events to tools account"
  }
}

# EventBridge target to send events to tools account default bus
resource "aws_cloudwatch_event_target" "to_tools_bus" {
  rule      = aws_cloudwatch_event_rule.ecr_push_forward.name
  target_id = "ToolsBus"
  arn       = "arn:aws:events:${data.aws_region.current.name}:${local.tools_account_id}:event-bus/default"
  role_arn  = aws_iam_role.eventbridge_cross_account.arn
}