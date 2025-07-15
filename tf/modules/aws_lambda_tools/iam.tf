# IAM role for EventBridge to trigger CodePipeline
resource "aws_iam_role" "eventbridge_pipeline" {
  name = "${var.app}-tools-eventbridge-pipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "EventBridge role to trigger CodePipeline"
  }
}

# Policy for EventBridge to trigger CodePipeline
resource "aws_iam_role_policy" "eventbridge_pipeline" {
  name = "${var.app}-tools-eventbridge-pipeline"
  role = aws_iam_role.eventbridge_pipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codepipeline:StartPipelineExecution"
        ]
        Resource = aws_codepipeline.deployment_pipeline.arn
      }
    ]
  })
}

# IAM role for CodePipeline
resource "aws_iam_role" "codepipeline" {
  name = "${var.app}-tools-codepipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "CodePipeline service role"
  }
}

# Policy for CodePipeline
resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.app}-tools-codepipeline"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 permissions for artifacts
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:GetObjectVersionTagging",
          "s3:PutObject",
          "s3:GetBucketVersioning",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      },
      # SNS permissions for manual approval
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.manual_approval.arn
      },
      # Cross-account assume role permissions for dev and prod deployments
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          local.dev_tools_cross_account_role_arn,
          local.prod_tools_cross_account_role_arn
        ]
      },
      # Lambda permissions for sync image actions
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.sync_image.arn
        ]
      }
    ]
  })
}

