# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Locals for computed values
locals {
  tools_account_id = data.aws_caller_identity.current.account_id
  region = data.aws_region.current.name
  
  # Pipeline name following existing pattern
  pipeline_name = "${var.app}-tools-pipeline"
  
  # Pipeline artifacts bucket
  pipeline_artifacts_bucket = "${var.app}-${local.tools_account_id}-tools-pipeline-artifacts"
  
  # Conventional names based on aws_lambda module patterns
  # These follow the naming conventions established in the aws_lambda module
  dev_ecr_repository_name = "${var.app}-dev"
  dev_codedeploy_app_name = "${var.app}-dev"
  dev_deployment_group_name = "${var.app}-dev"
  dev_lambda_function_name = "${var.app}-dev"
  dev_manual_deploy_lambda_name = "${var.app}-dev-manual-deploy"
  dev_deploy_lambda_name = "${var.app}-dev-deploy"
  dev_tools_cross_account_role_arn = "arn:aws:iam::${var.dev_account_id}:role/${var.app}-dev-tools-access"
  
  prod_ecr_repository_name = "${var.app}-prod"
  prod_codedeploy_app_name = "${var.app}-prod"
  prod_deployment_group_name = "${var.app}-prod"
  prod_lambda_function_name = "${var.app}-prod"
  prod_manual_deploy_lambda_name = "${var.app}-prod-manual-deploy"
  prod_deploy_lambda_name = "${var.app}-prod-deploy"
  prod_tools_cross_account_role_arn = "arn:aws:iam::${var.prod_account_id}:role/${var.app}-prod-tools-access"
}

# S3 bucket for pipeline artifacts
resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = local.pipeline_artifacts_bucket

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "CodePipeline artifacts for ${var.app}"
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket policy to allow cross-account CodeDeploy access
# CodeDeploy actions in the pipeline run with cross-account roles and need to read source.zip
resource "aws_s3_bucket_policy" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCodeDeployFetch"
        Effect    = "Allow"
        Principal = {
          AWS = [
            local.dev_tools_cross_account_role_arn,
            local.prod_tools_cross_account_role_arn,
            "arn:aws:iam::${var.dev_account_id}:role/${var.app}-dev-codedeploy",
            "arn:aws:iam::${var.prod_account_id}:role/${var.app}-prod-codedeploy"
          ]
        }
        Action = [
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionTagging"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      },
      {
        Sid       = "AllowCodePipelineAccess"
        Effect    = "Allow"
        Principal = {
          AWS = aws_iam_role.codepipeline.arn
        }
        Action = [
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionTagging",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      }
    ]
  })
}
