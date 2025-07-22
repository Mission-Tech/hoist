# IAM role for CodePipeline
resource "aws_iam_role" "codepipeline" {
    name = "${var.org}-${var.app}-${local.env}-codepipeline"
    
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
    
    tags = local.tags
}

# IAM policy for CodePipeline
resource "aws_iam_role_policy" "codepipeline" {
    name = "codepipeline-policy"
    role = aws_iam_role.codepipeline.id
    
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "s3:GetBucketVersioning",
                    "s3:GetBucketLocation"
                ]
                Resource = [
                    # Read from CI upload bucket (source)
                    aws_s3_bucket.ci_upload.arn,
                    "${aws_s3_bucket.ci_upload.arn}/*",
                    # Read/write to pipeline artifact store
                    aws_s3_bucket.tf_artifacts.arn,
                    "${aws_s3_bucket.tf_artifacts.arn}/*"
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "codebuild:BatchGetBuilds",
                    "codebuild:StartBuild"
                ]
                Resource = [
                    module.tf_runner.codebuild_terraform_plan_project_arn
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "lambda:InvokeFunction"
                ]
                Resource = [
                    module.lambda_consolidate_results.lambda_function_arn
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ]
                Resource = [
                    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.org}-${var.app}-${local.env}-*",
                    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.org}-${var.app}-${local.env}-*:*"
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "events:PutRule",
                    "events:PutTargets",
                    "events:DescribeRule"
                ]
                Resource = "arn:aws:events:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:rule/*"
            },
            {
                Effect = "Allow"
                Action = "sts:AssumeRole"
                Resource = [
                    "arn:aws:iam::${var.dev_account_id}:role/${local.conventional_dev_codebuild_plan_invoker_name}",
                    "arn:aws:iam::${var.prod_account_id}:role/${local.conventional_prod_codebuild_plan_invoker_name}"
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "kms:Decrypt",
                    "kms:DescribeKey",
                    "kms:GenerateDataKey",
                    "kms:CreateGrant",
                    "kms:RetireGrant"
                ]
                Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:kms/${var.pipeline_artifacts_kms_key_id}"
            }
        ]
    })
}
