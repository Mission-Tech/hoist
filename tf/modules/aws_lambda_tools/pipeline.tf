# CodePipeline v2 for deployment orchestration
resource "aws_codepipeline" "deployment_pipeline" {
  name           = local.pipeline_name
  role_arn       = aws_iam_role.codepipeline.arn
  pipeline_type  = "V2"

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"

    # Use the shared KMS key for encryption
    encryption_key {
      id   = data.aws_kms_key.pipeline_artifacts.arn
      type = "KMS"
    }
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
        S3Bucket             = aws_s3_bucket.pipeline_artifacts.bucket
        S3ObjectKey          = "source-dev.zip"
        PollForSourceChanges = false
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
        S3Bucket             = aws_s3_bucket.pipeline_artifacts.bucket
        S3ObjectKey          = "source-prod.zip"
        PollForSourceChanges = false
      }
    }
  }

  # Run migrations BEFORE deployments
  # Ensures database schema is updated before new code runs
  dynamic "stage" {
    for_each = var.enable_migrations ? [1] : []
    content {
      name = "RunDevMigrations"

      action {
        name            = "RunMigrations"
        category        = "Build"
        owner           = "AWS"
        provider        = "CodeBuild"
        version         = "1"
        input_artifacts = ["dev_source"]
        region          = var.dev_region
        role_arn        = "arn:aws:iam::${local.dev_account_id}:role/${local.conventional_dev_codebuild_migrations_invoker_name}"

        configuration = {
          ProjectName = local.conventional_dev_codebuild_migrations_project_name

          EnvironmentVariables = jsonencode([
            {
              name  = "IMAGE_TAG"
              value = "#{variables.DEV_IMAGE_TAG}"
              type  = "PLAINTEXT"
            },
            {
              name  = "ECR_IMAGE"
              value = "${local.dev_account_id}.dkr.ecr.${var.dev_region}.amazonaws.com/${local.dev_ecr_repository_name}:#{variables.DEV_IMAGE_TAG}"
              type  = "PLAINTEXT"
            },
            {
              name  = "ECR_REGISTRY"
              value = "${local.dev_account_id}.dkr.ecr.${var.dev_region}.amazonaws.com"
              type  = "PLAINTEXT"
            }
          ])
        }
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
          "accountId" : local.dev_account_id,
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

  # Run migrations BEFORE deployments
  # Ensures database schema is updated before new code runs
  dynamic "stage" {
    for_each = var.enable_migrations ? [1] : []
    content {
      name = "RunProdMigrations"

      action {
        name            = "RunMigrations"
        category        = "Build"
        owner           = "AWS"
        provider        = "CodeBuild"
        version         = "1"
        input_artifacts = ["prod_source"]
        region          = var.prod_region
        role_arn        = "arn:aws:iam::${local.prod_account_id}:role/${local.conventional_prod_codebuild_migrations_invoker_name}"

        configuration = {
          ProjectName = local.conventional_prod_codebuild_migrations_project_name

          EnvironmentVariables = jsonencode([
            {
              name  = "IMAGE_TAG"
              value = "#{variables.PROD_IMAGE_TAG}"
              type  = "PLAINTEXT"
            },
            {
              name  = "ECR_IMAGE"
              value = "${local.prod_account_id}.dkr.ecr.${var.prod_region}.amazonaws.com/${local.prod_ecr_repository_name}:#{variables.PROD_IMAGE_TAG}"
              type  = "PLAINTEXT"
            },
            {
              name  = "ECR_REGISTRY"
              value = "${local.prod_account_id}.dkr.ecr.${var.prod_region}.amazonaws.com"
              type  = "PLAINTEXT"
            }
          ])
        }
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
          "accountId" : local.prod_account_id,
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