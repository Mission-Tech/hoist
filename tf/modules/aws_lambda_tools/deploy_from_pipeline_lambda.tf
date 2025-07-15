# Lambda function to deploy from pipeline
locals {
  deploy_from_pipeline_lambda_name = "${var.app}-tools-deploy-from-pipeline"
}

# IAM role for deploy from pipeline Lambda
resource "aws_iam_role" "deploy_from_pipeline_lambda" {
  name = local.deploy_from_pipeline_lambda_name

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
    Description = "Role for deploy from pipeline Lambda"
  }
}

# Policy for deploy from pipeline Lambda
resource "aws_iam_role_policy" "deploy_from_pipeline_lambda" {
  name = local.deploy_from_pipeline_lambda_name
  role = aws_iam_role.deploy_from_pipeline_lambda.id

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
          "arn:aws:logs:${local.region}:${local.tools_account_id}:log-group:/aws/lambda/${local.deploy_from_pipeline_lambda_name}",
          "arn:aws:logs:${local.region}:${local.tools_account_id}:log-group:/aws/lambda/${local.deploy_from_pipeline_lambda_name}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codepipeline:PutJobSuccessResult",
          "codepipeline:PutJobFailureResult"
        ]
        Resource = "*" # Attempted granular permissions with no success
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
resource "aws_lambda_function" "deploy_from_pipeline" {
  filename         = data.archive_file.deploy_from_pipeline_lambda.output_path
  function_name    = local.deploy_from_pipeline_lambda_name
  role            = aws_iam_role.deploy_from_pipeline_lambda.arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 900  # 15 minutes to handle long deployments
  source_code_hash = data.archive_file.deploy_from_pipeline_lambda.output_base64sha256

  environment {
    variables = {
      APP_NAME = var.app
    }
  }

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "Deploys from pipeline and waits for completion"
  }
}

# Permission for CodePipeline to invoke the deploy-from-pipeline lambda
resource "aws_lambda_permission" "codepipeline_invoke" {
  statement_id  = "AllowCodePipelineInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.deploy_from_pipeline.function_name
  principal     = "codepipeline.amazonaws.com"
  source_arn    = aws_codepipeline.deployment_pipeline.arn
}

# Archive the Lambda function
data "archive_file" "deploy_from_pipeline_lambda" {
  type        = "zip"
  output_path = "${path.module}/deploy_from_pipeline_lambda.zip"
  
  source {
    content  = file("${path.module}/deploy_from_pipeline_lambda/index.py")
    filename = "index.py"
  }
}
