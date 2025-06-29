resource "aws_ecr_repository" "lambda_repository" {
  name                 = "${var.app}-${var.env}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "${var.app}-${var.env}"
    Module      = "hoist_lambda"
    Application = var.app
    Environment = var.env
    Description = "ECR repository for Lambda function container images"
  }
}

resource "aws_ecr_lifecycle_policy" "lambda_repository_policy" {
  repository = aws_ecr_repository.lambda_repository.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
