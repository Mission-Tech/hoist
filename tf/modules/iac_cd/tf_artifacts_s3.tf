# S3 bucket for CodePipeline artifact store (internal use only)
resource "aws_s3_bucket" "tf_artifacts" {
    bucket = "${var.org}-${var.app}-${local.env}-${data.aws_caller_identity.current.account_id}-pipeline"

    tags = merge(local.tags,{
        Name        = "${var.org}-${var.app}-${local.env}-${data.aws_caller_identity.current.account_id}-pipeline"
        Purpose     = "CodePipeline artifact store - internal use only"
    })
}

# Block public access
resource "aws_s3_bucket_public_access_block" "tf_artifacts" {
    bucket = aws_s3_bucket.tf_artifacts.id

    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

# Enable versioning for pipeline artifact integrity
resource "aws_s3_bucket_versioning" "tf_artifacts" {
    bucket = aws_s3_bucket.tf_artifacts.id

    versioning_configuration {
        status = "Enabled"
    }
}

# Use SSE-S3 encryption (not KMS) to avoid cross-account KMS complexity
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_artifacts" {
    bucket = aws_s3_bucket.tf_artifacts.id

    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "AES256"
        }
    }
}

# Lifecycle rule to clean up old artifacts
resource "aws_s3_bucket_lifecycle_configuration" "tf_artifacts" {
    bucket = aws_s3_bucket.tf_artifacts.id

    rule {
        id     = "cleanup-pipeline-artifacts"
        status = "Enabled"

        filter {}

        # Pipeline artifacts can be kept longer for debugging
        expiration {
            days = 90
        }

        noncurrent_version_expiration {
            noncurrent_days = 30
        }
    }
}

# No EventBridge needed - this is only for pipeline internal use

# TODO: Add bucket policy for cross-account access after confirming it works in same account
# The bucket policy below will be needed once we have dev/prod CodeBuild projects deployed
# and need cross-account access. For now, commenting out to avoid circular dependencies.

# # Bucket policy to allow cross-account access from dev/prod CodeBuild
# resource "aws_s3_bucket_policy" "tf_artifacts" {
#     bucket = aws_s3_bucket.tf_artifacts.id
# 
#     policy = jsonencode({
#         Version = "2012-10-17"
#         Statement = [
#             {
#                 Sid    = "AllowCrossAccountCodeBuildAccess"
#                 Effect = "Allow"
#                 Principal = {
#                     AWS = [
#                         "arn:aws:iam::${var.dev_account_id}:role/${local.conventional_dev_codebuild_plan_role_name}"
#                         # TODO: Uncomment after prod is deployed
#                         # "arn:aws:iam::${var.prod_account_id}:role/${local.conventional_prod_codebuild_plan_role_name}"
#                     ]
#                 }
#                 Action = [
#                     "s3:GetObject",
#                     "s3:GetObjectVersion"
#                 ]
#                 Resource = "${aws_s3_bucket.tf_artifacts.arn}/*"
#             },
#             {
#                 Sid    = "AllowCrossAccountCodeBuildListBucket"
#                 Effect = "Allow"
#                 Principal = {
#                     AWS = [
#                         "arn:aws:iam::${var.dev_account_id}:role/${local.conventional_dev_codebuild_plan_role_name}"
#                         # TODO: Uncomment after prod is deployed
#                         # "arn:aws:iam::${var.prod_account_id}:role/${local.conventional_prod_codebuild_plan_role_name}"
#                     ]
#                 }
#                 Action = [
#                     "s3:ListBucket",
#                     "s3:GetBucketLocation"
#                 ]
#                 Resource = aws_s3_bucket.tf_artifacts.arn
#             }
#         ]
#     })
# }
