# IAM role for CodePipeline
resource "aws_iam_role" "codepipeline" {
    name = "${var.org}-${var.app}-${var.env}-codepipeline"
    
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
                    aws_s3_bucket.terraform_artifacts.arn,
                    "${aws_s3_bucket.terraform_artifacts.arn}/*"
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "lambda:InvokeFunction"
                ]
                Resource = [
                    module.lambda_terraform_plan.lambda_function_arn,
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
                Resource = "arn:aws:logs:*:*:*"
            }
        ]
    })
}