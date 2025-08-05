locals {
    // github_oidc_provider_arn will use the provided ARN or construct it from the current account
    github_oidc_provider_arn = var.github_oidc_provider_arn != "" ? var.github_oidc_provider_arn : local.conventional_github_oidc_provider_arn
}

# Policy for GitHub Actions to upload to S3 with branch restrictions
resource "aws_iam_policy" "github_ci" {
    name        = "${var.org}-${var.app}-${local.env}-github-ci"
    description = "Policy for GitHub Actions to upload terraform artifacts to S3"

    policy = jsonencode({
        Version = "2012-10-17",
        Statement = [
            # Allow branch uploads ONLY for non-main branches
            {
                Sid    = "AllowBranchUploads"
                Effect = "Allow"
                Action = [
                    "s3:PutObject",
                    "s3:PutObjectTagging"
                ],
                Resource = "${aws_s3_bucket.ci_upload.arn}/branch/*",
                Condition = {
                    StringNotEquals = {
                        "token.actions.githubusercontent.com:ref" = "refs/heads/main"
                    }
                }
            },
            # Allow main uploads ONLY from main branch
            {
                Sid    = "AllowMainUploads"
                Effect = "Allow"
                Action = [
                    "s3:PutObject",
                    "s3:PutObjectTagging"
                ],
                Resource = "${aws_s3_bucket.ci_upload.arn}/main/*",
                Condition = {
                    StringEquals = {
                        "token.actions.githubusercontent.com:ref" = "refs/heads/main"
                    }
                }
            },
            # Debug: Allow main uploads with a different condition to test
            {
                Sid    = "DebugMainUploads"
                Effect = "Allow"
                Action = [
                    "s3:PutObject",
                    "s3:PutObjectTagging"
                ],
                Resource = "${aws_s3_bucket.ci_upload.arn}/main/*",
                Condition = {
                    StringLike = {
                        "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.app}:ref:refs/heads/main"
                    }
                }
            }
        ]
    })

    tags = local.tags
}

resource "aws_iam_role_policy_attachment" "github_terraform_upload" {
    role       = var.ci_role_name
    policy_arn = aws_iam_policy.github_ci.arn
}
