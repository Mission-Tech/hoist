# Lambda execution role for S3 trigger
resource "aws_iam_role" "lambda_s3_trigger" {
    name = "${var.org}-${var.app}-${local.env}-lambda-s3-trigger"
    
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

# S3 trigger Lambda policy
resource "aws_iam_role_policy" "lambda_s3_trigger" {
    name = "s3-trigger-policy"
    role = aws_iam_role.lambda_s3_trigger.id
    
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
                Resource = [
                    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${module.lambda_s3_trigger.lambda_function_name}",
                    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${module.lambda_s3_trigger.lambda_function_name}:*"
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "s3:GetObject",
                    "s3:HeadObject"
                ]
                Resource = "${aws_s3_bucket.tf_artifacts.arn}/*"
            },
            {
                Effect = "Allow"
                Action = "codepipeline:StartPipelineExecution"
                Resource = [
                    aws_codepipeline.branch.arn,
                    aws_codepipeline.main.arn
                ]
            }
        ]
    })
}

# Lambda function for S3 trigger using the serverless.tf module
module "lambda_s3_trigger" {
    source  = "terraform-aws-modules/lambda/aws"
    version = "6.7.0"

    function_name = "${var.org}-${var.app}-${local.env}-s3-trigger"
    handler       = "lambda_trigger.lambda_handler"
    runtime       = "python3.11"
    architectures = ["arm64"]
    timeout       = 60

    source_path = "${path.module}/src/s3-trigger-lambda"

    # Attach the IAM role
    create_role = false
    lambda_role = aws_iam_role.lambda_s3_trigger.arn

    environment_variables = {
        BRANCH_PIPELINE_NAME = aws_codepipeline.branch.name
        MAIN_PIPELINE_NAME   = aws_codepipeline.main.name
    }

    tags = local.tags
}

# Permission for S3 to invoke Lambda
resource "aws_lambda_permission" "s3_trigger" {
    statement_id  = "AllowExecutionFromS3"
    action        = "lambda:InvokeFunction"
    function_name = module.lambda_s3_trigger.lambda_function_name
    principal     = "s3.amazonaws.com"
    source_arn    = aws_s3_bucket.tf_artifacts.arn
}

# S3 bucket notification to trigger Lambda
resource "aws_s3_bucket_notification" "terraform_artifacts" {
    bucket = aws_s3_bucket.tf_artifacts.arn
    
    lambda_function {
        lambda_function_arn = module.lambda_s3_trigger.lambda_function_arn
        events              = ["s3:ObjectCreated:*"]
        filter_prefix       = "branch/"
        filter_suffix       = ".zip"
    }
    
    depends_on = [aws_lambda_permission.s3_trigger]
}
