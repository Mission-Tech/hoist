# Allow dev account to put events to tools account default event bus
resource "aws_cloudwatch_event_bus_policy" "allow_dev_put" {
  event_bus_name = "default"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowDevToPut"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${local.dev_account_id}:root" }
      Action    = "events:PutEvents"
      Resource  = "arn:aws:events:${local.region}:${local.tools_account_id}:event-bus/default"
    }]
  })
}

# EventBridge rule to match ECR push events forwarded from dev account
resource "aws_cloudwatch_event_rule" "dev_ecr_push" {
  name        = "${var.app}-from-dev-ecr"
  description = "Dev → Tools: ECR push"

  event_pattern = jsonencode({
    account     = [local.dev_account_id]
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Action"]
    detail      = { 
      action-type = ["PUSH"]
      repository-name = [local.dev_ecr_repository_name]
    }
  })

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "ECR push event rule from dev account"
  }
}

# EventBridge target to trigger prepare-deployment Lambda when ECR push happens
resource "aws_cloudwatch_event_target" "trigger_prepare_lambda" {
  rule      = aws_cloudwatch_event_rule.dev_ecr_push.name
  target_id = "TriggerPrepareLambda"
  arn       = aws_lambda_function.prepare_deployment.arn
}

# Permission for EventBridge to invoke prepare-deployment Lambda
resource "aws_lambda_permission" "eventbridge_invoke_prepare" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.prepare_deployment.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.dev_ecr_push.arn
}