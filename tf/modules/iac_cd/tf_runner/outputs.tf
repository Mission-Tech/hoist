output "codebuild_terraform_plan_project_name" {
    description = "Name of the CodeBuild project for terraform plan"
    value       = aws_codebuild_project.terraform_plan.name
}

output "codebuild_terraform_plan_project_arn" {
    description = "ARN of the CodeBuild project for terraform plan"  
    value       = aws_codebuild_project.terraform_plan.arn
}

output "codepipeline_build_invoker_role_arn" {
    description = "ARN of the role that CodePipeline can assume to invoke CodeBuild"
    value       = aws_iam_role.codepipeline_build_invoker.arn
}

output "codebuild_terraform_plan_role_arn" {
    description = "ARN of the CodeBuild service role for terraform plan"
    value       = aws_iam_role.codebuild_terraform_plan.arn
}
