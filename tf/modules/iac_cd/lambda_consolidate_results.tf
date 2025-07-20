# Lambda execution role for consolidate results
resource "aws_iam_role" "lambda_consolidate_results" {
    name = "${var.org}-${var.app}-${var.env}-lambda-consolidate"
    
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
    
    tags = local.tags
}

# Policy for consolidate results Lambda
resource "aws_iam_role_policy" "lambda_consolidate_results" {
    name = "consolidate-results-policy"
    role = aws_iam_role.lambda_consolidate_results.id
    
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ]
                Resource = "arn:aws:logs:*:*:*"
            },
            {
                Effect = "Allow"
                Action = "s3:GetObject"
                Resource = "${aws_s3_bucket.terraform_artifacts.arn}/*"
            },
            {
                Effect = "Allow"
                Action = [
                    "codepipeline:PutJobSuccessResult",
                    "codepipeline:PutJobFailureResult"
                ]
                Resource = "arn:aws:codepipeline:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:job/*"
            }
        ]
    })
}

# Lambda function for consolidating results using the serverless.tf module
module "lambda_consolidate_results" {
    source  = "terraform-aws-modules/lambda/aws"
    version = "6.7.0"

    function_name = "${var.org}-${var.app}-${var.env}-consolidate-results"
    handler       = "lambda_consolidate_results.lambda_handler"
    runtime       = "python3.11"
    architectures = ["arm64"]
    timeout       = 300
    memory_size   = 512

    source_path = "${path.module}/src/consolidate-results-lambda"

    # Attach the IAM role
    create_role = false
    lambda_role = aws_iam_role.lambda_consolidate_results.arn

    environment_variables = {
        SLACK_WEBHOOK_URL = var.slack_cd_webhook_url
    }

    tags = local.tags
}