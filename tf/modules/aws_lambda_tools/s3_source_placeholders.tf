# Placeholder source files for CodePipeline S3 source actions
#
# These files are required by CodePipeline because the deploy actions specify
# input_artifacts, even though the deploy-from-pipeline Lambda doesn't actually
# use the artifact contents. All deployment info comes from pipeline variables.
#
# The files contain minimal JSON metadata to satisfy CodePipeline requirements.

# Create placeholder deployment metadata JSON
data "archive_file" "source_dev_placeholder" {
  type        = "zip"
  output_path = "${path.module}/source-dev-placeholder.zip"

  source {
    content = jsonencode({
      sourceImageUri = "placeholder"
      devImageUri    = "placeholder"
      prodImageUri   = "placeholder"
      imageTag       = "placeholder"
      digest         = ""
      repository     = "placeholder"
      sourceAccount  = "placeholder"
      region         = var.dev_region
      timestamp      = "2025-01-01T00:00:00Z"
    })
    filename = "deployment-metadata.json"
  }
}

data "archive_file" "source_prod_placeholder" {
  type        = "zip"
  output_path = "${path.module}/source-prod-placeholder.zip"

  source {
    content = jsonencode({
      sourceImageUri = "placeholder"
      devImageUri    = "placeholder"
      prodImageUri   = "placeholder"
      imageTag       = "placeholder"
      digest         = ""
      repository     = "placeholder"
      sourceAccount  = "placeholder"
      region         = var.prod_region
      timestamp      = "2025-01-01T00:00:00Z"
    })
    filename = "deployment-metadata.json"
  }
}

# Upload placeholder files to S3
resource "aws_s3_object" "source_dev" {
  bucket = aws_s3_bucket.pipeline_artifacts.bucket
  key    = "source-dev.zip"
  source = data.archive_file.source_dev_placeholder.output_path
  etag   = data.archive_file.source_dev_placeholder.output_md5

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "Placeholder source artifact for dev pipeline stage"
  }

  depends_on = [aws_s3_bucket.pipeline_artifacts]
}

resource "aws_s3_object" "source_prod" {
  bucket = aws_s3_bucket.pipeline_artifacts.bucket
  key    = "source-prod.zip"
  source = data.archive_file.source_prod_placeholder.output_path
  etag   = data.archive_file.source_prod_placeholder.output_md5

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "Placeholder source artifact for prod pipeline stage"
  }

  depends_on = [aws_s3_bucket.pipeline_artifacts]
}
