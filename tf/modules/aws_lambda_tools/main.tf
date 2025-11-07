# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Get account IDs from Parameter Store
data "aws_ssm_parameter" "dev_account_id" {
  name = "/coreinfra/shared/dev_account_id"
}

data "aws_ssm_parameter" "prod_account_id" {
  name = "/coreinfra/shared/prod_account_id"
}

# Locals for computed values
locals {
  tools_account_id = data.aws_caller_identity.current.account_id
  region = data.aws_region.current.name
  dev_account_id = nonsensitive(data.aws_ssm_parameter.dev_account_id.value)
  prod_account_id = nonsensitive(data.aws_ssm_parameter.prod_account_id.value)
  
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
  dev_tools_cross_account_role_arn = "arn:aws:iam::${local.dev_account_id}:role/${var.app}-dev-tools-access"
  
  prod_ecr_repository_name = "${var.app}-prod"
  prod_codedeploy_app_name = "${var.app}-prod"
  prod_deployment_group_name = "${var.app}-prod"
  prod_lambda_function_name = "${var.app}-prod"
  prod_manual_deploy_lambda_name = "${var.app}-prod-manual-deploy"
  prod_deploy_lambda_name = "${var.app}-prod-deploy"
  prod_tools_cross_account_role_arn = "arn:aws:iam::${local.prod_account_id}:role/${var.app}-prod-tools-access"
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
        Sid       = "AllowCodeDeployBucketAccess"
        Effect    = "Allow"
        Principal = {
          AWS = [
            local.dev_tools_cross_account_role_arn,
            local.prod_tools_cross_account_role_arn,
            "arn:aws:iam::${local.dev_account_id}:role/${var.app}-dev-codedeploy",
            "arn:aws:iam::${local.prod_account_id}:role/${var.app}-prod-codedeploy"
          ]
        }
        Action = [
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.pipeline_artifacts.arn
      },
      {
        Sid       = "AllowCodeDeployObjectAccess"
        Effect    = "Allow"
        Principal = {
          AWS = [
            local.dev_tools_cross_account_role_arn,
            local.prod_tools_cross_account_role_arn,
            "arn:aws:iam::${local.dev_account_id}:role/${var.app}-dev-codedeploy",
            "arn:aws:iam::${local.prod_account_id}:role/${var.app}-prod-codedeploy"
          ]
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionTagging"
        ]
        Resource = "${aws_s3_bucket.pipeline_artifacts.arn}/*"
      },
      {
        Sid       = "AllowCodePipelineBucketAccess"
        Effect    = "Allow"
        Principal = {
          AWS = aws_iam_role.codepipeline.arn
        }
        Action = [
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:ListBucketMultipartUploads",
          "s3:GetBucketVersioning",
          "s3:GetBucketLocation",
          "s3:GetBucketAcl",
          "s3:GetBucketCORS",
          "s3:GetBucketRequestPayment",
          "s3:GetBucketLogging",
          "s3:GetBucketNotification",
          "s3:GetBucketPolicy",
          "s3:GetBucketPolicyStatus",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetBucketObjectLockConfiguration",
          "s3:GetBucketTagging",
          "s3:GetBucketWebsite",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketOwnershipControls"
        ]
        Resource = aws_s3_bucket.pipeline_artifacts.arn
      },
      {
        Sid       = "AllowCodePipelineObjectAccess"
        Effect    = "Allow"
        Principal = {
          AWS = aws_iam_role.codepipeline.arn
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectAcl",
          "s3:GetObjectAttributes",
          "s3:GetObjectLegalHold",
          "s3:GetObjectRetention",
          "s3:GetObjectTagging",
          "s3:GetObjectTorrent",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionAttributes",
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionTorrent",
          "s3:ListMultipartUploadParts",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:PutObjectTagging",
          "s3:PutObjectVersionAcl",
          "s3:PutObjectVersionTagging",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
          "s3:DeleteObjectTagging",
          "s3:DeleteObjectVersionTagging",
          "s3:RestoreObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = "${aws_s3_bucket.pipeline_artifacts.arn}/*"
      }
    ]
  })
}
