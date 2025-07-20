# Lambda execution role for terraform plan
resource "aws_iam_role" "lambda_terraform_plan" {
    name = "${var.org}-${var.app}-${var.env}-lambda-terraform-plan"
    
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Principal = {
                    Service = "lambda.amazonaws.com"
                }
            }
        ]
    })
    
    tags = local.tags
}

# Policy for terraform plan Lambda
resource "aws_iam_role_policy" "lambda_terraform_plan" {
    name = "terraform-plan-policy"
    role = aws_iam_role.lambda_terraform_plan.id
    
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ]
                Resource = "arn:aws:logs:*:*:*"
            },
            {
                Effect = "Allow"
                Action = [
                    "s3:GetObject",
                    "s3:PutObject"
                ]
                Resource = [
                    "${aws_s3_bucket.terraform_artifacts.arn}/*"
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "codepipeline:PutJobSuccessResult",
                    "codepipeline:PutJobFailureResult"
                ]
                Resource = "arn:aws:codepipeline:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:job/*"
            },
            {
                Effect = "Allow"
                Action = "sts:AssumeRole"
                Resource = [
                    "arn:aws:iam::${var.dev_account_id}:role/${var.org}-${var.app}-${var.env}-terraform-executor",
                    "arn:aws:iam::${var.prod_account_id}:role/${var.org}-${var.app}-${var.env}-terraform-executor"
                ]
            }
        ]
    })
}

# Lambda function for terraform plan using the serverless.tf module
module "lambda_terraform_plan" {
    source  = "terraform-aws-modules/lambda/aws"
    version = "6.7.0"

    function_name = "${var.org}-${var.app}-${var.env}-terraform-plan"
    handler       = "bootstrap"
    runtime       = "provided.al2023"
    architectures = ["arm64"]
    timeout       = 900
    memory_size   = 1024

    # Build the Go Lambda function
    source_path = {
        path     = "${path.module}/src/tf-plan-lambda"
        commands = [
            "go mod download",
            "go mod tidy", 
            "GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -ldflags '-s -w' -o bootstrap .",
            # Download OpenTofu binary
            "curl -L https://github.com/opentofu/opentofu/releases/download/v${var.opentofu_version}/tofu_${var.opentofu_version}_linux_arm64.zip -o tofu.zip",
            "unzip -o tofu.zip",
            "rm tofu.zip",
            "chmod +x tofu",
            # Package everything into the deployment ZIP
            ":zip"
        ]
    }

    build_in_docker = true
    docker_image    = "public.ecr.aws/sam/build-go1.x"

    # Attach the IAM role
    create_role = false
    lambda_role = aws_iam_role.lambda_terraform_plan.arn

    environment_variables = {
        CROSS_ACCOUNT_ROLE_NAME = "${var.org}-${var.app}-${var.env}-terraform-executor"
        TOOLS_ACCOUNT_ID        = data.aws_caller_identity.current.account_id
        DEV_ACCOUNT_ID          = var.dev_account_id
        PROD_ACCOUNT_ID         = var.prod_account_id
    }

    tags = local.tags
}