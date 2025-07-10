resource "aws_ecr_repository" "lambda_repository" {
  name                 = "${var.app}-${var.env}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name        = "${var.app}-${var.env}"
    Module      = "hoist_lambda"
    Application = var.app
    Environment = var.env
    Description = "ECR repository for Lambda function container images"
  }
}

# Note: Lifecycle policy removed - images are now managed by cleanup Lambda
# This ensures precise control over which images are deleted and when
