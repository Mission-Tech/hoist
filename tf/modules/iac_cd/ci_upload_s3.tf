# S3 bucket for CI to upload terraform bundles
resource "aws_s3_bucket" "ci_upload" {
    bucket = "${var.org}-${var.app}-${local.env}-${data.aws_caller_identity.current.account_id}-ci-upload"

    tags = merge(local.tags,{
        Name        = "${var.org}-${var.app}-${local.env}-${data.aws_caller_identity.current.account_id}-ci-upload"
        Purpose     = "CI uploads terraform bundles here to trigger pipelines"
    })
}

# Block public access
resource "aws_s3_bucket_public_access_block" "ci_upload" {
    bucket = aws_s3_bucket.ci_upload.id

    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
}

# Enable versioning for race-free concurrent uploads
resource "aws_s3_bucket_versioning" "ci_upload" {
    bucket = aws_s3_bucket.ci_upload.id

    versioning_configuration {
        status = "Enabled"
    }
}

# Aggressive lifecycle rule - CI artifacts can be deleted quickly
resource "aws_s3_bucket_lifecycle_configuration" "ci_upload" {
    bucket = aws_s3_bucket.ci_upload.id

    rule {
        id     = "cleanup-ci-uploads"
        status = "Enabled"

        filter {}

        # Delete current versions after 7 days
        expiration {
            days = 7
        }

        # Delete old versions after 1 day
        noncurrent_version_expiration {
            noncurrent_days = 1
        }
    }
}

# Enable EventBridge notifications
resource "aws_s3_bucket_notification" "ci_upload" {
    bucket = aws_s3_bucket.ci_upload.id
    eventbridge = true
}

# Bucket policy to allow CodePipeline access
resource "aws_s3_bucket_policy" "ci_upload" {
    bucket = aws_s3_bucket.ci_upload.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Sid    = "AllowCodePipelineAccess"
                Effect = "Allow"
                Principal = {
                    AWS = aws_iam_role.codepipeline.arn
                }
                Action = [
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:GetBucketVersioning",
                    "s3:GetBucketLocation"
                ]
                Resource = [
                    aws_s3_bucket.ci_upload.arn,
                    "${aws_s3_bucket.ci_upload.arn}/*"
                ]
            }
        ]
    })
}

# Output for CI to know where to upload
output "ci_upload_bucket" {
    value = aws_s3_bucket.ci_upload.id
    description = "S3 bucket where CI should upload terraform bundles"
}