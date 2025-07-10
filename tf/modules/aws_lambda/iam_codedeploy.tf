resource "aws_iam_role" "codedeploy" {
  name = "${var.app}-${var.env}-codedeploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "CodeDeploy service role for ${var.app}-${var.env}"
  }
}

resource "aws_iam_role_policy_attachment" "codedeploy_lambda" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambda"
}

resource "aws_iam_role_policy_attachment" "codedeploy_lambda_limited" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRoleForLambdaLimited"
}

# Additional policy for CodeDeploy to invoke hook functions
resource "aws_iam_role_policy" "codedeploy_hooks" {
  name = "${var.app}-${var.env}-codedeploy-hooks"
  role = aws_iam_role.codedeploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.health_check.arn,
          "${aws_lambda_function.health_check.arn}:*"
        ]
      }
    ]
  })
}

# Additional policy for CodeDeploy to access S3 deployment artifacts
resource "aws_iam_role_policy" "codedeploy_s3" {
  name = "${var.app}-${var.env}-codedeploy-s3"
  role = aws_iam_role.codedeploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = [
          "${aws_s3_bucket.codedeploy_appspec.arn}/*"
        ]
      }
    ]
  })
}