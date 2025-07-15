# Lambda function to prepare deployment artifacts from ECR push event
locals {
  prepare_deployment_lambda_name = "${var.app}-tools-prepare-deployment"
}

# IAM role for prepare deployment Lambda
resource "aws_iam_role" "prepare_deployment_lambda" {
  name = local.prepare_deployment_lambda_name

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
    Description = "Role for prepare deployment Lambda"
  }
}

# Policy for prepare deployment Lambda
resource "aws_iam_role_policy" "prepare_deployment_lambda" {
  name = local.prepare_deployment_lambda_name
  role = aws_iam_role.prepare_deployment_lambda.id

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
          "arn:aws:logs:${local.region}:${local.tools_account_id}:log-group:/aws/lambda/${local.prepare_deployment_lambda_name}",
          "arn:aws:logs:${local.region}:${local.tools_account_id}:log-group:/aws/lambda/${local.prepare_deployment_lambda_name}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codepipeline:StartPipelineExecution"
        ]
        Resource = aws_codepipeline.deployment_pipeline.arn
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
resource "aws_lambda_function" "prepare_deployment" {
  filename         = data.archive_file.prepare_deployment_lambda.output_path
  function_name    = local.prepare_deployment_lambda_name
  role            = aws_iam_role.prepare_deployment_lambda.arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 300  # 5 minutes for Lambda updates
  source_code_hash = data.archive_file.prepare_deployment_lambda.output_base64sha256

  environment {
    variables = {
      PIPELINE_NAME = local.pipeline_name
      ARTIFACTS_BUCKET = aws_s3_bucket.pipeline_artifacts.bucket
      DEV_LAMBDA_FUNCTION = local.dev_lambda_function_name
      PROD_LAMBDA_FUNCTION = local.prod_lambda_function_name
      DEV_CROSS_ACCOUNT_ROLE = local.dev_tools_cross_account_role_arn
      PROD_CROSS_ACCOUNT_ROLE = local.prod_tools_cross_account_role_arn
      DEV_REGION = var.dev_region
      PROD_REGION = var.prod_region
      DEV_ACCOUNT_ID = local.dev_account_id
      PROD_ACCOUNT_ID = local.prod_account_id
      APP_NAME = var.app
    }
  }

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "Prepares deployment artifacts for pipeline"
  }
}

# Archive the Lambda function
data "archive_file" "prepare_deployment_lambda" {
  type        = "zip"
  output_path = "${path.module}/prepare_deployment_lambda.zip"
  
  source {
    content  = file("${path.module}/prepare_deployment_lambda/index.py")
    filename = "index.py"
  }
}