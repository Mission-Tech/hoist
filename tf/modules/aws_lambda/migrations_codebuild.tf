# Database Migrations Pipeline
#
# Architecture:
# 1. CodePipeline (tools account) triggers cross-account CodeBuild in dev/prod
# 2. CodeBuild runs in VPC private subnets with dedicated security group
# 3. Pulls Lambda container image from ECR and runs /migrate entrypoint
# 4. Uses IAM auth for database access (no passwords)
# 5. Migrations run BEFORE Lambda deployments in the pipeline
#
# Security:
# - Dedicated security group (per-service pattern) whitelisted by croft for RDS access
# - KMS grants allow decryption of pipeline artifacts from tools account
# - IAM role scoped to: ECR pull, AppConfig read, RDS connect via IAM auth

# Security group for migrations CodeBuild
# Uses dedicated security group (per-service pattern) rather than sharing with Lambda
# This allows fine-grained control - croft module whitelists this SG for RDS access
resource "aws_security_group" "migrations" {
  count = var.enable_migrations ? 1 : 0

  name        = "${var.app}-${var.env}-migrations"
  description = "Security group for ${var.app}-${var.env} migrations CodeBuild"
  vpc_id      = data.aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound IPv4 traffic"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
    description      = "Allow all outbound IPv6 traffic"
  }

  tags = {
    Name        = "${var.app}-${var.env}-migrations"
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Purpose     = "migrations"
  }
}

# CodeBuild project for running database migrations
resource "aws_codebuild_project" "migrations" {
  count = var.enable_migrations ? 1 : 0

  name          = "${var.app}-${var.env}-migrations"
  description   = "Runs database migrations for ${var.app}-${var.env}"
  service_role  = aws_iam_role.migrations[0].arn
  build_timeout = 10 # 10 minutes timeout

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                      = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                       = "LINUX_CONTAINER"
    privileged_mode            = true # Required for Docker
    image_pull_credentials_type = "CODEBUILD"

    # Static environment variables
    environment_variable {
      name  = "AWS_REGION"
      value = data.aws_region.current.name
    }

    environment_variable {
      name  = "APPCONFIG_APPLICATION_ID"
      value = aws_appconfig_application.main.id
    }

    environment_variable {
      name  = "APPCONFIG_ENVIRONMENT_ID"
      value = aws_appconfig_environment.main.environment_id
    }

    environment_variable {
      name  = "APPCONFIG_CONFIG_PROFILE_ID"
      value = aws_appconfig_configuration_profile.config.configuration_profile_id
    }

    # Dynamic environment variables passed from CodePipeline:
    # - IMAGE_TAG
    # - ECR_IMAGE
    # - ECR_REGISTRY
  }

  # Run in VPC for RDS access with dedicated security group
  vpc_config {
    vpc_id             = data.aws_vpc.main.id
    subnets            = local.private_subnet_ids
    security_group_ids = [aws_security_group.migrations[0].id]
  }

  source {
    type      = "NO_SOURCE"
    buildspec = file("${path.module}/migrations_codebuild_buildspec.yml")
  }

  logs_config {
    cloudwatch_logs {
      group_name = "/aws/codebuild/${var.app}-${var.env}-migrations"
    }
  }

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Purpose     = "migrations"
  }
}
