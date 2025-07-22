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

# Attach ReadOnlyAccess for terraform plan to read arbitrary infrastructure
resource "aws_iam_role_policy_attachment" "lambda_terraform_plan_readonly" {
    role       = aws_iam_role.lambda_terraform_plan.name
    policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
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
                Resource = [
                    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${module.lambda_terraform_plan.lambda_function_name}",
                    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${module.lambda_terraform_plan.lambda_function_name}:*"
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "codepipeline:PutJobSuccessResult",
                    "codepipeline:PutJobFailureResult"
                ]
                # CodePipeline job operations don't support resource-level permissions
                Resource = "*"
            },
            {
                Effect = "Allow"
                Action = [
                    "ssm:GetParameter",
                    "ssm:GetParameters",
                    "ssm:GetParametersByPath"
                ]
                Resource = [
                    "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter${local.parameter_prefix}/*"
                ]
            },
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
        path     = "${path.module}/tf_plan_lambda"
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
        # Only rebuild when source files change, not on every run
        pip_requirements = false
        patterns = [
            "!.*/.*\\.txt",
            "!.*/.*\\.md"
        ]
    }

    build_in_docker = true
    docker_image    = "public.ecr.aws/sam/build-go1.x"
    
    # Only trigger rebuilds when Go files or OpenTofu version changes
    hash_extra = "${filebase64sha256("${path.module}/tf_plan_lambda/main.go")}-${var.opentofu_version}"
    
    # Prevent timestamp from being included in triggers
    trigger_on_package_timestamp = false

    # Attach the IAM role
    create_role = false
    lambda_role = aws_iam_role.lambda_terraform_plan.arn
    
    # Environment variables
    environment_variables = merge(
        {
            # Pass the parameter store prefix so Lambda knows where to look
            PARAMETER_STORE_PREFIX = local.parameter_prefix
        },
        # Add all tfvars as TF_VAR_ environment variables
        { for k, v in var.tfvars : "TF_VAR_${k}" => v }
    )

    tags = local.tags
}

# Allow CodePipeline from tools account to invoke this Lambda
resource "aws_lambda_permission" "allow_tools_codepipeline" {
    statement_id  = "AllowToolsCodePipelineInvoke"
    action        = "lambda:InvokeFunction"
    function_name = module.lambda_terraform_plan.lambda_function_name
    principal     = "codepipeline.amazonaws.com"
    source_account = var.tools_account_id
}
