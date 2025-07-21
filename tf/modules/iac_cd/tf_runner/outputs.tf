output "lambda_terraform_plan_function_name" {
    value = module.lambda_terraform_plan.lambda_function_name
    description = "Name of the terraform plan Lambda function"
}

output "lambda_terraform_plan_function_arn" {
    value = module.lambda_terraform_plan.lambda_function_arn
    description = "ARN of the terraform plan Lambda function"
}

output "lambda_codepipeline_invoke_role_arn" {
    value = aws_iam_role.codepipeline_lambda_invoker.arn
    description = "ARN of the role CodePipeline should assume to invoke the Lambda"
}