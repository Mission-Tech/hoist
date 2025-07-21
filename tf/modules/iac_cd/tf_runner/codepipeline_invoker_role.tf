# Cross-account role that CodePipeline in tools account can assume to invoke Lambda
resource "aws_iam_role" "codepipeline_lambda_invoker" {
    name = "${var.org}-${var.app}-${var.env}-codepipeline-lambda-invoker"
    
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

# Policy to allow invoking the Lambda
resource "aws_iam_role_policy" "codepipeline_lambda_invoker" {
    name = "invoke-lambda"
    role = aws_iam_role.codepipeline_lambda_invoker.id
    
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = "lambda:InvokeFunction"
                Resource = module.lambda_terraform_plan.lambda_function_arn
            }
        ]
    })
}