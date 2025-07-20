# S3 bucket for storing artifacts produced by CI before they're applied by the CD pipeline

# S3 bucket for storing terraform zip files from CI (lives in tools account)
resource "aws_s3_bucket" "tf_artifacts" {
    bucket = "${var.org}-${var.app}-${local.env}-${data.aws_caller_identity.current.account_id}-iac"

    tags = merge(local.tags,{
        Name        = "${var.org}-${var.app}-${local.env}-${data.aws_caller_identity.current.account_id}-iac"
        Purpose     = "Terraform artifact storage for IaC pipeline"
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

# Enable versioning to keep history of deployments
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
        id     = "cleanup-old-branch-artifacts"
        status = "Enabled"

        filter {
            prefix = "branch/"
        }

        expiration {
            days = 30
        }

        noncurrent_version_expiration {
            noncurrent_days = 7
        }
    }

    rule {
        id     = "cleanup-old-main-artifacts"
        status = "Enabled"

        filter {
            prefix = "main/"
        }

        noncurrent_version_expiration {
            noncurrent_days = 90
        }
    }
}
