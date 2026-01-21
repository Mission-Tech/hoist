output "app_security_group_id" {
  description = "The security group id of the app. Useful for adding it to other resources (e.g. rds)"
  value       = aws_security_group.lambda.id
}

output "app_base_url" {
  description = "The base URL to reach this app on the internet"
  value       = "https://${local.custom_domain_name}"
}

output "app_iam_role_name" {
  description = "The IAM role for the app at runtime. In this case, the lambda execution role"
  value       = aws_iam_role.lambda_execution.name
}

output "migrations_security_group_id" {
  description = "Security group ID for migrations CodeBuild (null if migrations disabled)"
  value       = var.enable_migrations ? aws_security_group.migrations[0].id : null
}

output "migrations_iam_role_name" {
  description = "IAM role name for migrations CodeBuild (null if migrations disabled)"
  value       = var.enable_migrations ? aws_iam_role.migrations[0].name : null
}

output "appconfig_application_id" {
  description = "The AppConfig application ID for this app/environment"
  value       = aws_appconfig_application.main.id
}

output "appconfig_environment_id" {
  description = "The AppConfig environment ID for this app/environment"
  value       = aws_appconfig_environment.main.environment_id
}

output "appconfig_config_profile_id" {
  description = "The AppConfig configuration profile ID for unencrypted config"
  value       = aws_appconfig_configuration_profile.config.configuration_profile_id
}

output "appconfig_secrets_profile_id" {
  description = "The AppConfig configuration profile ID for encrypted secrets"
  value       = aws_appconfig_configuration_profile.secrets.configuration_profile_id
}

output "app_subnet_ids" {
  description = "The subnet IDs where the app Lambda runs"
  value       = data.aws_subnets.private.ids
}

output "ecr_image_uri" {
  description = "The ECR image URI for the app's Docker image"
  value       = "${aws_ecr_repository.main.repository_url}:${var.env}"
}