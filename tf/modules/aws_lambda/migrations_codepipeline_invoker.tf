# Cross-account IAM role for tools account CodePipeline to invoke migrations CodeBuild
resource "aws_iam_role" "codepipeline_migration_invoker" {
  count = var.enable_migrations ? 1 : 0
  name  = "${var.app}-${var.env}-codepipeline-migration-invoker"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${local.tools_account_id}:role/${var.app}-tools-codepipeline"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Purpose     = "migrations-codepipeline-invoker"
  }
}

# IAM policy allowing CodePipeline to start and monitor migrations CodeBuild
resource "aws_iam_role_policy" "codepipeline_migration_invoker" {
  count = var.enable_migrations ? 1 : 0
  role  = aws_iam_role.codepipeline_migration_invoker[0].id
  name  = "codepipeline-migration-invoker-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ]
      Resource = [aws_codebuild_project.migrations[0].arn]
    }]
  })
}
