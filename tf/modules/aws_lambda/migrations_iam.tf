# IAM role for migrations CodeBuild project
resource "aws_iam_role" "migrations" {
  count = var.enable_migrations ? 1 : 0
  name  = "${var.app}-${var.env}-migrations"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Purpose     = "migrations"
  }
}

# IAM policy for migrations CodeBuild project
resource "aws_iam_role_policy" "migrations" {
  count = var.enable_migrations ? 1 : 0
  role  = aws_iam_role.migrations[0].id
  name  = "migrations-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR: Pull images from app's repository
      {
        Effect = "Allow"
        Action = ["ecr:GetAuthorizationToken"]
        # Note: GetAuthorizationToken doesn't support resource-level permissions
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
      },
      # Note: RDS IAM auth permissions (if applicable) should be granted via the DB module (e.g. croft)
      # S3: Read pipeline artifacts from tools account (CodePipeline downloads input artifacts)
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::${local.tools_pipeline_artifacts_bucket}/*"
      },
      # AppConfig: Read config profile (unencrypted)
      # Note: GetConfiguration checks permissions at application, environment, and configurationprofile levels
      {
        Effect = "Allow"
        Action = [
          "appconfig:GetConfiguration"
        ]
        Resource = [
          "arn:aws:appconfig:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:application/${aws_appconfig_application.main.id}",
          "arn:aws:appconfig:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:application/${aws_appconfig_application.main.id}/environment/${aws_appconfig_environment.main.environment_id}",
          "arn:aws:appconfig:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:application/${aws_appconfig_application.main.id}/configurationprofile/${aws_appconfig_configuration_profile.config.configuration_profile_id}"
        ]
      },
      # CloudWatch Logs: Write to specific log group
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${aws_codebuild_project.migrations[0].name}",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${aws_codebuild_project.migrations[0].name}:*"
        ]
      },
      # VPC: Network interfaces (required for VPC-enabled CodeBuild)
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeVpcs",
          "ec2:CreateNetworkInterfacePermission"
        ]
        # Note: EC2 describe actions don't support resource-level permissions
        Resource = "*"
      }
    ]
  })
}
