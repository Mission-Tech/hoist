# S3 bucket for storing CodeDeploy AppSpec files
resource "aws_s3_bucket" "codedeploy_appspec" {
  bucket = "${var.app}-${var.env}-codedeploy-appspec"

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "CodeDeploy AppSpec storage for ${var.app}-${var.env}"
  }
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "codedeploy_appspec" {
  bucket = aws_s3_bucket.codedeploy_appspec.id
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "codedeploy_appspec" {
  bucket = aws_s3_bucket.codedeploy_appspec.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "codedeploy_appspec" {
  bucket = aws_s3_bucket.codedeploy_appspec.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}