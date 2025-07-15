# IAM role for CodeDeploy hook Lambda functions
resource "aws_iam_role" "codedeploy_hook_lambda" {
  name = "${var.app}-${var.env}-codedeploy-hook"

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
    Description = "Role for CodeDeploy hook Lambda functions"
  }
}

# Policy for hook Lambda functions
resource "aws_iam_role_policy" "codedeploy_hook_lambda" {
  name = "${var.app}-${var.env}-codedeploy-hook"
  role = aws_iam_role.codedeploy_hook_lambda.id

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
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.app}-${var.env}-health-check",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.app}-${var.env}-health-check:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:PutLifecycleEventHookExecutionStatus"
        ]
        Resource = [
          "arn:aws:codedeploy:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:deploymentgroup:${aws_codedeploy_app.lambda.name}/${aws_codedeploy_deployment_group.lambda.deployment_group_name}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:GetDeployment",
          "codedeploy:ListDeploymentTargets",
          "codedeploy:GetDeploymentTarget"
        ]
        Resource = [
          "arn:aws:codedeploy:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:deploymentgroup:${aws_codedeploy_app.lambda.name}/${aws_codedeploy_deployment_group.lambda.deployment_group_name}"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          "${aws_lambda_function.main.arn}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.codedeploy_appspec.arn}/*"
        ]
      }
    ]
  })
}

# Health check Lambda function for BeforeAllowTraffic hook
resource "aws_lambda_function" "health_check" {
  function_name = "${var.app}-${var.env}-health-check"
  role          = aws_iam_role.codedeploy_hook_lambda.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60
  
  filename         = data.archive_file.health_check_lambda.output_path
  source_code_hash = data.archive_file.health_check_lambda.output_base64sha256

  environment {
    variables = {
      FUNCTION_NAME = aws_lambda_function.main.function_name
    }
  }

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Health check for CodeDeploy BeforeAllowTraffic hook"
  }
}

# Archive for health check Lambda
data "archive_file" "health_check_lambda" {
  type        = "zip"
  output_path = "${path.module}/health_check_lambda.zip"
  
  source {
    content  = file("${path.module}/health_check_lambda/index.py")
    filename = "index.py"
  }
}