# CodePipeline v2 for deployment orchestration
resource "aws_codepipeline" "deployment_pipeline" {
  name           = local.pipeline_name
  role_arn       = aws_iam_role.codepipeline.arn
  pipeline_type  = "V2"

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  variable {
    name = "DEV_IMAGE_TAG"
    default_value = "latest"
  }

  variable {
    name = "DEV_IMAGE_DIGEST"
    default_value = ""
  }

  variable {
    name = "PROD_IMAGE_TAG"
    default_value = "latest"
  }

  variable {
    name = "PROD_IMAGE_DIGEST"
    default_value = ""
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
      name            = "Deploy"
      category        = "Invoke"
      owner           = "AWS"
      provider        = "Lambda"
      version         = "1"
      input_artifacts = ["dev_source"]
      region          = var.dev_region

      configuration = {
        FunctionName   = aws_lambda_function.deploy_from_pipeline.function_name
        UserParameters = jsonencode({
          "accountId" : var.dev_account_id,
          "region" : var.dev_region,
          "repositoryName" : local.dev_ecr_repository_name,
          "crossAccountRoleArn" : local.dev_tools_cross_account_role_arn,
          "deployLambdaName" : local.dev_deploy_lambda_name,
          "imageTag" : "#{variables.DEV_IMAGE_TAG}",
          "imageDigest" : "#{variables.DEV_IMAGE_DIGEST}"
        })
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
      name            = "Deploy"
      category        = "Invoke"
      owner           = "AWS"
      provider        = "Lambda"
      version         = "1"
      input_artifacts = ["prod_source"]
      region          = var.prod_region

      configuration = {
        FunctionName   = aws_lambda_function.deploy_from_pipeline.function_name
        UserParameters = jsonencode({
          "accountId" : var.prod_account_id,
          "region" : var.prod_region,
          "repositoryName" : local.prod_ecr_repository_name,
          "crossAccountRoleArn" : local.prod_tools_cross_account_role_arn,
          "deployLambdaName" : local.prod_deploy_lambda_name,
          "imageTag" : "#{variables.PROD_IMAGE_TAG}",
          "imageDigest" : "#{variables.PROD_IMAGE_DIGEST}"
        })
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