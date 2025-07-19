locals {
    // github_oidc_provider_arn will use the provided ARN or construct it from the current account
    github_oidc_provider_arn = var.github_oidc_provider_arn != "" ? var.github_oidc_provider_arn : local.conventional_github_oidc_provider_arn
}

resource "aws_iam_role" "github_deploy" {
    name = "${var.app}-${var.env}-github-ci"

    assume_role_policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
            {
                Effect = "Allow",
                Principal = {
                    Federated = local.github_oidc_provider_arn
                },
                Action = "sts:AssumeRoleWithWebIdentity",
                Condition = {
                    StringEquals = {
                        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
                        "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.app}:*"
                    }
                }
            }
        ]
    })

    tags = {
        Name        = "${var.app}-${var.env}-ci"
        Description = "GitHub-assumable CI role for ${var.app} in ${var.env} environment"
        Application = var.app
        Environment = var.env
    }
}
