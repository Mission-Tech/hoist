# Cross-account role for tools account to manage this environment

locals {
  tools_cross_account_role_name = "${var.app}-${var.env}-tools-access"
  tools_codepipeline_role_arn = "arn:aws:iam::${var.tools_account_id}:role/${var.app}-tools-codepipeline"
  tools_prepare_deployment_role_arn = "arn:aws:iam::${var.tools_account_id}:role/${var.app}-tools-prepare-deployment"
  tools_sync_image_role_arn = "arn:aws:iam::${var.tools_account_id}:role/${var.app}-tools-sync-image"
}

# IAM role for tools account to access this environment
resource "aws_iam_role" "tools_access" {
  name = local.tools_cross_account_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = [
            local.tools_codepipeline_role_arn,
            local.tools_prepare_deployment_role_arn,
            local.tools_sync_image_role_arn
          ]
        }
      }
    ]
  })

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Cross-account role for tools account access"
  }
}

# Policy for tools account to manage deployments
resource "aws_iam_role_policy" "tools_access" {
  name = local.tools_cross_account_role_name
  role = aws_iam_role.tools_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CodeDeploy permissions using conventional naming
      {
        Effect = "Allow"
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:GetApplicationRevision",
          "codedeploy:RegisterApplicationRevision"
        ]
        Resource = [
          "arn:aws:codedeploy:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:application:${var.app}-${var.env}",
          "arn:aws:codedeploy:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:deploymentgroup:${var.app}-${var.env}/${var.app}-${var.env}",
          "arn:aws:codedeploy:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:deploymentconfig:${var.app}-${var.env}",
          "arn:aws:codedeploy:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:deploymentconfig:CodeDeployDefault.LambdaAllAtOnce"
        ]
      },
      # Lambda permissions for updating functions and managing versions
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
      },
      # S3 permissions for accessing pipeline artifacts
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionTagging"
        ]
        Resource = [
          "arn:aws:s3:::${var.app}-${var.tools_account_id}-tools-pipeline-artifacts",
          "arn:aws:s3:::${var.app}-${var.tools_account_id}-tools-pipeline-artifacts/*"
        ]
      }
    ]
  })
}
