resource "aws_iam_policy" "github_deploy_ecr" {
    name = "${var.app}-${var.env}-ecr"

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "ecr:PutImage",
                    "ecr:InitiateLayerUpload",
                    "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload"
                ]
                Resource = aws_ecr_repository.lambda_repository.arn
            },
            {
                Effect = "Allow"
                Action = [
                    "ecr:GetAuthorizationToken"
                ]
                Resource = "*"
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "github_deploy_ecr" {
    role       = var.ci_assume_role_name
    policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
