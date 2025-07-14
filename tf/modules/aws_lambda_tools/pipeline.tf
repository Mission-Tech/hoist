# CodePipeline v2 for deployment orchestration
resource "aws_codepipeline" "deployment_pipeline" {
  name           = local.pipeline_name
  role_arn       = aws_iam_role.codepipeline.arn
  pipeline_type  = "V2"

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "SourceDev"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["dev_source"]

      configuration = {
        S3Bucket    = aws_s3_bucket.pipeline_artifacts.bucket
        S3ObjectKey = "source-dev.zip"
      }
    }

    action {
      name             = "SourceProd"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      output_artifacts = ["prod_source"]

      configuration = {
        S3Bucket    = aws_s3_bucket.pipeline_artifacts.bucket
        S3ObjectKey = "source-prod.zip"
      }
    }
  }

  stage {
    name = "DeployToDev"

    action {
      name             = "Deploy"
      category         = "Deploy"
      owner            = "AWS"
      provider         = "CodeDeploy"
      version          = "1"
      input_artifacts  = ["dev_source"]
      region           = var.dev_region
      role_arn         = local.dev_tools_cross_account_role_arn

      configuration = {
        ApplicationName     = local.dev_codedeploy_app_name
        DeploymentGroupName = local.dev_deployment_group_name
      }
    }
  }

  stage {
    name = "ManualApproval"

    action {
      name     = "ManualApproval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn = aws_sns_topic.manual_approval.arn
        CustomData      = "Please review the dev deployment and approve for production deployment"
      }
    }
  }

  stage {
    name = "DeployToProd"

    action {
      name             = "Deploy"
      category         = "Deploy"
      owner            = "AWS"
      provider         = "CodeDeploy"
      version          = "1"
      input_artifacts  = ["prod_source"]
      region           = var.prod_region
      role_arn         = local.prod_tools_cross_account_role_arn

      configuration = {
        ApplicationName     = local.prod_codedeploy_app_name
        DeploymentGroupName = local.prod_deployment_group_name
      }
    }
  }

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "Deployment pipeline for ${var.app}"
  }
}