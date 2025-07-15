# Data source for VPC
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = [local.conventional_coreinfra_vpc_name]
  }
}

# Data source for private subnets
data "aws_subnets" "private" {
  filter {
    name   = "tag:Name"
    values = local.conventional_coreinfra_subnets
  }
}

# Security group for Lambda function
resource "aws_security_group" "lambda" {
  name        = "${var.app}-${var.env}-lambda"
  description = "Security group for ${var.app}-${var.env} Lambda function"
  vpc_id      = data.aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name        = "${var.app}-${var.env}-lambda"
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
  }
}

# Lambda execution role
resource "aws_iam_role" "lambda_execution" {
  name = "${var.app}-${var.env}-lambda-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Lambda execution role for ${var.app}-${var.env}"
  }
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach VPC access policy for Lambda
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# ECR access policy for Lambda execution role
resource "aws_iam_role_policy" "lambda_ecr_access" {
  name = "${var.app}-${var.env}-lambda-ecr-access"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = aws_ecr_repository.lambda_repository.arn
      }
    ]
  })
}

# Data source to get the most recent image
data "aws_ecr_image" "latest" {
  repository_name = aws_ecr_repository.lambda_repository.name
  most_recent     = true
}

# Lambda function
resource "aws_lambda_function" "main" {
  function_name = "${var.app}-${var.env}"
  role          = aws_iam_role.lambda_execution.arn
  
  package_type = "Image"
  # Use the most recent image by digest
  image_uri    = "${aws_ecr_repository.lambda_repository.repository_url}@${data.aws_ecr_image.latest.image_digest}"
  
  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size
  
  # Publish a version on creation
  publish = true
  
  environment {
    variables = {
        "hoist_app" : var.app
        "hoist_env" : var.env
    }
  }

  vpc_config {
    subnet_ids         = data.aws_subnets.private.ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  lifecycle {
    # Ignore changes to image_uri since CodeDeploy will manage deployments
    # Ignore publish to prevent creating new versions on every apply
    ignore_changes = [image_uri, publish]
  }

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Lambda function for ${var.app}-${var.env}"
  }
}

# Lambda alias for blue/green deployments
resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Live alias for blue/green deployments"
  function_name    = aws_lambda_function.main.function_name
  function_version = aws_lambda_function.main.version
  
  lifecycle {
    ignore_changes = [function_version, routing_config]  # Let CodeDeploy manage version updates and routing
  }
}
