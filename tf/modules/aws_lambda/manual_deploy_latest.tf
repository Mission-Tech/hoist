# Manual deploy Lambda function
resource "aws_lambda_function" "manual_deploy" {
  function_name = "${var.app}-${var.env}-manual-deploy"
  role          = aws_iam_role.manual_deploy.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60
  
  filename         = data.archive_file.manual_deploy_lambda.output_path
  source_code_hash = data.archive_file.manual_deploy_lambda.output_base64sha256

  environment {
    variables = {
      DEPLOY_FUNCTION_NAME = aws_lambda_function.deploy.function_name
      ECR_REPOSITORY_NAME   = aws_ecr_repository.lambda_repository.name
    }
  }

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Manual deployment trigger for ${var.app}-${var.env}"
  }
}

# IAM role for manual deploy Lambda
resource "aws_iam_role" "manual_deploy" {
  name = "${var.app}-${var.env}-manual-deploy-latest"

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
    Description = "Role for manual deploy Lambda"
  }
}

# Policy for manual deploy Lambda
resource "aws_iam_role_policy" "manual_deploy" {
  name = "${var.app}-${var.env}-manual-deploy-latest"
  role = aws_iam_role.manual_deploy.id

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
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.app}-${var.env}-manual-deploy-latest",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.app}-${var.env}-manual-deploy-latest:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:ListImages"
        ]
        Resource = [
          aws_ecr_repository.lambda_repository.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.deploy.arn
        ]
      }
    ]
  })
}

# Archive for manual deploy Lambda
data "archive_file" "manual_deploy_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/manual_deploy_latest_lambda"
  output_path = "${path.module}/manual_deploy_lambda.zip"
}
