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

output "codebuild_terraform_apply_project_name" {
    description = "Name of the CodeBuild project for terraform apply"
    value       = aws_codebuild_project.terraform_apply.name
}

output "codebuild_terraform_apply_project_arn" {
    description = "ARN of the CodeBuild project for terraform apply"  
    value       = aws_codebuild_project.terraform_apply.arn
}

output "codebuild_terraform_apply_role_arn" {
    description = "ARN of the CodeBuild service role for terraform apply"
    value       = aws_iam_role.codebuild_terraform_apply.arn
}

output "codebuild_terraform_apply_auto_project_name" {
    description = "Name of the CodeBuild project for terraform apply auto"
    value       = var.enable_auto_apply ? aws_codebuild_project.terraform_apply_auto[0].name : null
}

output "codebuild_terraform_apply_auto_project_arn" {
    description = "ARN of the CodeBuild project for terraform apply auto"  
    value       = var.enable_auto_apply ? aws_codebuild_project.terraform_apply_auto[0].arn : null
}

output "runner_security_group_id" {
  description = "ID of the security group of the terraform runner, to grant it additional network access if necessary."
  value       = aws_security_group.terraform_runner.id
}
