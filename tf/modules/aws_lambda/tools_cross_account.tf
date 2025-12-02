# Cross-account role for tools account to manage this environment

# Get tools account ID from Parameter Store
data "aws_ssm_parameter" "tools_account_id" {
  name = "/coreinfra/shared/tools_account_id"
}

locals {
  tools_account_id = nonsensitive(data.aws_ssm_parameter.tools_account_id.value)
  tools_cross_account_role_name = "${var.app}-${var.env}-tools-access"
  tools_codepipeline_role_arn = "arn:aws:iam::${local.tools_account_id}:role/${var.app}-tools-codepipeline"
  tools_prepare_deployment_role_arn = "arn:aws:iam::${local.tools_account_id}:role/${var.app}-tools-prepare-deployment"
  tools_deploy_from_pipeline_role_arn = "arn:aws:iam::${local.tools_account_id}:role/${var.app}-tools-deploy-from-pipeline"
  tools_pipeline_artifacts_bucket = "${var.app}-${local.tools_account_id}-tools-pipeline-artifacts"
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
            local.tools_deploy_from_pipeline_role_arn
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
      # Lambda permissions for invoking deploy function
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
