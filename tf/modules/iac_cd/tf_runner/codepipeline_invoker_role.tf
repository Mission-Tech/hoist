# Cross-account role that CodePipeline in tools account can assume to invoke CodeBuild
resource "aws_iam_role" "codepipeline_build_invoker" {
    name = "${var.org}-${var.app}-${var.env}-codepipeline-build-invoker"
    
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    AWS = var.tools_codepipeline_role_arn
                }
                Action = "sts:AssumeRole"
            }
        ]
    })
    
    tags = local.tags
}

# Policy to allow starting CodeBuild
resource "aws_iam_role_policy" "codepipeline_build_invoker" {
    name = "start-build"
    role = aws_iam_role.codepipeline_build_invoker.id
    
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "codebuild:BatchGetBuilds",
                    "codebuild:StartBuild"
                ]
                Resource = compact([
                    aws_codebuild_project.terraform_plan.arn,
                    aws_codebuild_project.terraform_apply.arn,
                    var.enable_auto_apply ? aws_codebuild_project.terraform_apply_auto[0].arn : ""
                ])
            },
            {
                # Allow reading/writing artifacts from the tools account pipeline bucket
                Effect = "Allow"
                Action = [
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject"
                ]
                Resource = "arn:aws:s3:::${local.conventional_tools_pipeline_artifacts_bucket}/*"
            },
            {
                Effect = "Allow"
                Action = [
                    "s3:GetBucketLocation",
                    "s3:ListBucket"
                ]
                Resource = "arn:aws:s3:::${local.conventional_tools_pipeline_artifacts_bucket}"
            }
        ]
    })
}