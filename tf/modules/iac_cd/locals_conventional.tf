# Inputs that are created by other terraform modules that we're using 
# because the names are conventional.

locals {
    # Created by coreinfra (github.com/mission-tech/coreinfra
    conventional_github_oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
    
    conventional_dev_codebuild_plan_project_name = "${var.org}-${var.app}-dev-terraform-plan"
    conventional_prod_codebuild_plan_project_name = "${var.org}-${var.app}-prod-terraform-plan"
    
    conventional_dev_codebuild_plan_invoker_name = "${var.org}-${var.app}-dev-codepipeline-build-invoker"
    conventional_prod_codebuild_plan_invoker_name = "${var.org}-${var.app}-prod-codepipeline-build-invoker"
    
    # CodeBuild service role names created by tf_runner module in dev/prod accounts
    conventional_dev_codebuild_plan_role_name = "${var.org}-${var.app}-dev-codebuild-terraform-plan"
    conventional_prod_codebuild_plan_role_name = "${var.org}-${var.app}-prod-codebuild-terraform-plan"
}
