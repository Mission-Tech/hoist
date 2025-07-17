output "app_security_group_id" {
    description = "The security group id of the app. Useful for adding it to other resources (e.g. rds)"
    value       = aws_security_group.lambda.id
}
