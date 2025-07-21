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
