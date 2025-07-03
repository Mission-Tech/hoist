resource "aws_iam_policy" "tfstate_access" {
  count       = var.tfstate_access_role_name != "" ? 1 : 0
  name        = "${var.tfstate_access_role_name}-tfstate-access"
  description = "Policy to allow access to Terraform state S3 bucket and DynamoDB table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketVersioning"
        ]
        Resource = "arn:aws:s3:::coreinfra-tfstate-${var.org}-${var.env}"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:HeadObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::coreinfra-tfstate-${var.org}-${var.env}/${var.app}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:*:*:table/coreinfra-tfstate-lock-${var.org}-${var.env}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "tfstate_access" {
  count      = var.tfstate_access_role_name != "" ? 1 : 0
  role       = var.tfstate_access_role_name
  policy_arn = aws_iam_policy.tfstate_access[0].arn
}
