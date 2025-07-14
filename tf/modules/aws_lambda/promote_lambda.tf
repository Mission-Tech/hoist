# Promote Lambda - only created in prod environment when dev_account_id is provided
# Cross-account role - only created in dev environment when prod_account_id is provided
locals {
  promote_lambda_name = "${var.app}-${var.env}-promote"
  cross_account_role_name = "${var.app}-${var.env}-cross-account-read"
  create_promote_lambda = var.env == "prod" && var.dev_account_id != null
  create_cross_account_role = var.env == "dev" && var.prod_account_id != null
}

# IAM role for the promote Lambda function
resource "aws_iam_role" "promote_lambda" {
  count = local.create_promote_lambda ? 1 : 0
  name  = local.promote_lambda_name

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
    Description = "Role for promote Lambda"
  }
}

# Policy for promote Lambda
resource "aws_iam_role_policy" "promote_lambda" {
  count = local.create_promote_lambda ? 1 : 0
  name  = local.promote_lambda_name
  role  = aws_iam_role.promote_lambda[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.promote_lambda_name}",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.promote_lambda_name}:*"
        ]
      },
      # Cross-account assume role to read dev deployments
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "arn:aws:iam::${var.dev_account_id}:role/${var.app}-${var.env}-cross-account-read"
      },
      # ECR access to verify prod images
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = aws_ecr_repository.lambda_repository.arn
      },
      # ECR auth token
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      # Invoke manual deploy lambda
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.manual_deploy.arn
      }
    ]
  })
}

# Lambda function for promoting deployments
resource "aws_lambda_function" "promote" {
  count            = local.create_promote_lambda ? 1 : 0
  filename         = data.archive_file.promote_lambda[0].output_path
  function_name    = local.promote_lambda_name
  role             = aws_iam_role.promote_lambda[0].arn
  handler          = "index.handler"
  runtime          = "python3.11"
  timeout          = 300  # 5 minutes
  source_code_hash = data.archive_file.promote_lambda[0].output_base64sha256

  environment {
    variables = {
      APP_NAME                     = var.app
      ENV_NAME                     = var.env
      DEV_ACCOUNT_ID              = var.dev_account_id
      MANUAL_DEPLOY_FUNCTION_NAME = aws_lambda_function.manual_deploy.function_name
      AWS_REGION                  = data.aws_region.current.name
    }
  }

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Promotes deployments from dev to prod"
  }
}

# Archive the promote Lambda function
data "archive_file" "promote_lambda" {
  count       = local.create_promote_lambda ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/promote_lambda"
  output_path = "${path.module}/promote_lambda.zip"
}

# Cross-account role that allows prod to read dev deployment data
resource "aws_iam_role" "cross_account_read" {
  count = local.create_cross_account_role ? 1 : 0
  name  = local.cross_account_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.prod_account_id}:role/${var.app}-prod-promote"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Cross-account role for prod to read dev deployment data"
  }
}

# Policy for cross-account role to read dev deployment data
resource "aws_iam_role_policy" "cross_account_read" {
  count = local.create_cross_account_role ? 1 : 0
  name  = local.cross_account_role_name
  role  = aws_iam_role.cross_account_read[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CodeDeploy read permissions
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
      },
      # S3 read permissions for AppSpec files
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.codedeploy_appspec.arn}/*"
      },
      # Lambda read permissions to get function versions
      {
        Effect = "Allow"
        Action = [
          "lambda:GetFunction"
        ]
        Resource = [
          "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.app}-${var.env}",
          "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.app}-${var.env}:*"
        ]
      },
      # ECR read permissions to get image details
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = aws_ecr_repository.lambda_repository.arn
      },
      # ECR auth token
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      }
    ]
  })
}