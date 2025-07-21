# Include the tf_runner module for the Lambda function in tools account
module "tf_runner" {
    source = "./tf_runner"
    
    app  = var.app
    env  = local.env
    org  = var.org
    repo = var.repo
    tags = var.tags
    
    opentofu_version = var.opentofu_version
    tools_account_id = data.aws_caller_identity.current.account_id
    tools_codepipeline_role_arn = aws_iam_role.codepipeline.arn
}
