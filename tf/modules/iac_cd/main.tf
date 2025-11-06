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
    pipeline_artifacts_kms_key_arn = data.aws_kms_key.pipeline_artifacts.arn
    enable_auto_apply = true  # Enable for tools environment
    
    # Pass terraform variables
    tfvars = {
        org = var.org
        env = local.env
        aws_account_id = data.aws_caller_identity.current.account_id
        # Add environment-specific variables
        dev_account_id = var.dev_account_id
        prod_account_id = var.prod_account_id
        github_org = var.github_org
        opentofu_version = var.opentofu_version
    }
    
    # Add any sensitive variables here
    tfvars_sensitive = {
        slack_cd_webhook_url = var.slack_cd_webhook_url
    }
    
    # Root module directory for tools environment
    root_module_dir = "tf/tools"
}
