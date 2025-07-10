# Cleanup Lambda function
resource "aws_lambda_function" "cleanup" {
  function_name = "${var.app}-${var.env}-cleanup"
  role          = aws_iam_role.cleanup.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300  # 5 minutes for cleanup operations
  
  filename         = data.archive_file.cleanup_lambda.output_path
  source_code_hash = data.archive_file.cleanup_lambda.output_base64sha256

  environment {
    variables = {
      ECR_REPOSITORY_NAME     = aws_ecr_repository.lambda_repository.name
      APPSPEC_BUCKET_NAME     = aws_s3_bucket.codedeploy_appspec.bucket
      CODEDEPLOY_APP_NAME     = aws_codedeploy_app.lambda.name
      CODEDEPLOY_GROUP_NAME   = aws_codedeploy_deployment_group.lambda.deployment_group_name
      RETAIN_COUNT            = "10"
      SUCCESSFUL_DEPLOY_RETAIN = "3"
    }
  }

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Cleanup old ECR images and AppSpec files for ${var.app}-${var.env}"
  }
}

# IAM role for cleanup Lambda
resource "aws_iam_role" "cleanup" {
  name = "${var.app}-${var.env}-cleanup"

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
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Role for cleanup Lambda"
  }
}

# Policy for cleanup Lambda
resource "aws_iam_role_policy" "cleanup" {
  name = "${var.app}-${var.env}-cleanup"
  role = aws_iam_role.cleanup.id

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
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.app}-${var.env}-cleanup",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.app}-${var.env}-cleanup:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:ListImages",
          "ecr:BatchDeleteImage"
        ]
        Resource = [
          aws_ecr_repository.lambda_repository.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.codedeploy_appspec.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:DeleteObject",
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.codedeploy_appspec.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:ListDeployments",
          "codedeploy:GetDeployment"
        ]
        Resource = [
          aws_codedeploy_app.lambda.arn,
          "arn:aws:codedeploy:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:deploymentgroup:${aws_codedeploy_app.lambda.name}/${aws_codedeploy_deployment_group.lambda.deployment_group_name}"
        ]
      }
    ]
  })
}

# EventBridge rule for successful CodeDeploy deployments
resource "aws_cloudwatch_event_rule" "deployment_success" {
  name        = "${var.app}-${var.env}-deployment-success"
  description = "Trigger cleanup on successful CodeDeploy deployment"

  event_pattern = jsonencode({
    source      = ["aws.codedeploy"]
    detail-type = ["CodeDeploy Deployment State-change Notification"]
    detail = {
      application-name = [aws_codedeploy_app.lambda.name]
      deployment-group = [aws_codedeploy_deployment_group.lambda.deployment_group_name]
      state           = ["SUCCESS"]
    }
  })

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "CodeDeploy success event rule"
  }
}

# EventBridge target for cleanup Lambda
resource "aws_cloudwatch_event_target" "cleanup_lambda" {
  rule      = aws_cloudwatch_event_rule.deployment_success.name
  target_id = "CleanupLambda"
  arn       = aws_lambda_function.cleanup.arn
}

# Permission for EventBridge to invoke cleanup Lambda
resource "aws_lambda_permission" "cleanup_eventbridge" {
  statement_id  = "AllowEventBridgeInvokeCleanup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.deployment_success.arn
}

# Archive for cleanup Lambda
data "archive_file" "cleanup_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/cleanup_lambda"
  output_path = "${path.module}/cleanup_lambda.zip"
}