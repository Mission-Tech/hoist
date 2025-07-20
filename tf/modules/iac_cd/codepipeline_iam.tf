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
                    "s3:GetBucketVersioning"
                ]
                Resource = [
                    aws_s3_bucket.tf_artifacts.arn,
                    "${aws_s3_bucket.tf_artifacts.arn}/*"
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "lambda:InvokeFunction"
                ]
                Resource = [
                    "arn:aws:lambda:${data.aws_region.current.name}:${var.dev_account_id}:function:${var.org}-${var.app}-dev-terraform-plan",
                    "arn:aws:lambda:${data.aws_region.current.name}:${var.prod_account_id}:function:${var.org}-${var.app}-prod-terraform-plan",
                    "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.org}-${var.app}-tools-terraform-plan",
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
            }
        ]
    })
}
