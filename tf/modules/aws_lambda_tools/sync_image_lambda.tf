# Lambda function to sync ECR image to target Lambda function
locals {
  sync_image_lambda_name = "${var.app}-tools-sync-image"
}

# IAM role for sync image Lambda
resource "aws_iam_role" "sync_image_lambda" {
  name = local.sync_image_lambda_name

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
    Description = "Role for sync image Lambda"
  }
}

# Policy for sync image Lambda
resource "aws_iam_role_policy" "sync_image_lambda" {
  name = local.sync_image_lambda_name
  role = aws_iam_role.sync_image_lambda.id

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
          "arn:aws:logs:${local.region}:${local.tools_account_id}:log-group:/aws/lambda/${local.sync_image_lambda_name}",
          "arn:aws:logs:${local.region}:${local.tools_account_id}:log-group:/aws/lambda/${local.sync_image_lambda_name}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codepipeline:PutJobSuccessResult",
          "codepipeline:PutJobFailureResult"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          local.dev_tools_cross_account_role_arn,
          local.prod_tools_cross_account_role_arn
        ]
      }
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "sync_image" {
  filename         = data.archive_file.sync_image_lambda.output_path
  function_name    = local.sync_image_lambda_name
  role            = aws_iam_role.sync_image_lambda.arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 300  # 5 minutes for Lambda updates
  source_code_hash = data.archive_file.sync_image_lambda.output_base64sha256

  environment {
    variables = {
      DEV_LAMBDA_FUNCTION = local.dev_lambda_function_name
      PROD_LAMBDA_FUNCTION = local.prod_lambda_function_name
      DEV_CROSS_ACCOUNT_ROLE = local.dev_tools_cross_account_role_arn
      PROD_CROSS_ACCOUNT_ROLE = local.prod_tools_cross_account_role_arn
      DEV_REGION = var.dev_region
      PROD_REGION = var.prod_region
      DEV_ACCOUNT_ID = var.dev_account_id
      PROD_ACCOUNT_ID = var.prod_account_id
      APP_NAME = var.app
    }
  }

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "Syncs ECR images to target Lambda functions"
  }
}

# Archive the Lambda function
data "archive_file" "sync_image_lambda" {
  type        = "zip"
  output_path = "${path.module}/sync_image_lambda.zip"
  
  source {
    content  = file("${path.module}/sync_image_lambda/index.py")
    filename = "index.py"
  }
}