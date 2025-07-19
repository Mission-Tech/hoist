output "ci_iam_role_name" {
    description = "Name of the role for github actions CI to assume"
    value = aws_iam_role.github_deploy.name
}
