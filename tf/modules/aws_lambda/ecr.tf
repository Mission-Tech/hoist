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

# ECR repository policy to allow Lambda service access
resource "aws_ecr_repository_policy" "lambda_access" {
  repository = aws_ecr_repository.lambda_repository.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaECRImageRetrievalPolicy"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
      }
    ]
  })
}

# Note: Lifecycle policy removed - images are now managed by cleanup Lambda
# This ensures precise control over which images are deleted and when
