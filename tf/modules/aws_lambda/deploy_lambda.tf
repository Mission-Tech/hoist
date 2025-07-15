# Local variables
locals {
  deploy_lambda_name = "${var.app}-${var.env}-deploy"
}

# IAM role for the deploy Lambda function
resource "aws_iam_role" "deploy_lambda" {
  name = local.deploy_lambda_name

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
    Description = "Role for deploy Lambda"
  }
}

# Policy for deploy Lambda to create CodeDeploy deployments
resource "aws_iam_role_policy" "deploy_lambda" {
  name = local.deploy_lambda_name
  role = aws_iam_role.deploy_lambda.id

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
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.deploy_lambda_name}",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.deploy_lambda_name}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision"
        ]
        Resource = [
          aws_codedeploy_app.lambda.arn,
          "arn:aws:codedeploy:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:deploymentgroup:${aws_codedeploy_app.lambda.name}/${aws_codedeploy_deployment_group.lambda.deployment_group_name}",
          "arn:aws:codedeploy:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:deploymentconfig:${aws_codedeploy_deployment_config.lambda_deployment_config.deployment_config_name}",
          "arn:aws:codedeploy:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:deploymentconfig:CodeDeployDefault.LambdaAllAtOnce"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          "${aws_s3_bucket.codedeploy_appspec.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:UpdateFunctionCode",
          "lambda:PublishVersion",
          "lambda:GetAlias",
          "lambda:UpdateAlias"
        ]
        Resource = [
          "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.app}-${var.env}",
          "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.app}-${var.env}:*"
        ]
      }
    ]
  })
}

# Lambda function to trigger CodeDeploy
resource "aws_lambda_function" "deploy" {
  filename         = data.archive_file.deploy_lambda.output_path
  function_name    = local.deploy_lambda_name
  role            = aws_iam_role.deploy_lambda.arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 60
  source_code_hash = data.archive_file.deploy_lambda.output_base64sha256

  environment {
    variables = {
      CODEDEPLOY_APP_NAME    = aws_codedeploy_app.lambda.name
      DEPLOYMENT_GROUP_NAME  = aws_codedeploy_deployment_group.lambda.deployment_group_name
      LAMBDA_FUNCTION_NAME   = "${var.app}-${var.env}"
      HEALTH_CHECK_FUNCTION_NAME = aws_lambda_function.health_check.function_name
      APPSPEC_BUCKET = aws_s3_bucket.codedeploy_appspec.bucket
    }
  }

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Triggers CodeDeploy deployments"
  }
}

# Archive the Lambda function
data "archive_file" "deploy_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/deploy_lambda"
  output_path = "${path.module}/deploy_lambda.zip"
}

# EventBridge rule and automatic triggers removed - deploy_lambda is now only called by pipeline or manual_deploy
