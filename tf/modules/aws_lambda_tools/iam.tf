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
          "s3:GetObjectAcl",
          "s3:PutObject",
          "s3:GetBucketVersioning",
          "s3:GetBucketLocation",
          "s3:GetBucketAcl",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.pipeline_artifacts.arn,
          "${aws_s3_bucket.pipeline_artifacts.arn}/*"
        ]
      },
      # KMS permissions for artifact encryption/decryption
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
          "kms:CreateGrant",
          "kms:RetireGrant"
        ]
        Resource = data.aws_kms_key.pipeline_artifacts.arn
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
        Resource = concat(
          [
            local.dev_tools_cross_account_role_arn,
            local.prod_tools_cross_account_role_arn
          ],
          var.enable_migrations ? [
            "arn:aws:iam::${local.dev_account_id}:role/${local.conventional_dev_codebuild_migrations_invoker_name}",
            "arn:aws:iam::${local.prod_account_id}:role/${local.conventional_prod_codebuild_migrations_invoker_name}"
          ] : []
        )
      },
      # Lambda permissions for deploy-from-pipeline function
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.deploy_from_pipeline.arn
        ]
      }
    ]
  })
}

