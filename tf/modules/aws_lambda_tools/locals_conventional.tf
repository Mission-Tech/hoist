# Inputs that are created by other terraform modules that we're using
# because the names are conventional.

locals {
    # Created by coreinfra
    conventional_slack_cd_webhook_url_parameterstore_path = "/coreinfra/shared/slack_cd_webhook_url"
    conventional_pipeline_kms_key_alias = "${var.org}-coreinfra-tools-pipeline-artifacts"

    # Migration CodeBuild project names (created by aws_lambda module)
    conventional_dev_codebuild_migrations_project_name = "${var.app}-dev-migrations"
    conventional_prod_codebuild_migrations_project_name = "${var.app}-prod-migrations"

    # Migration CodeBuild IAM role names (created by aws_lambda module)
    conventional_dev_codebuild_migrations_role_name = "${var.app}-dev-migrations"
    conventional_prod_codebuild_migrations_role_name = "${var.app}-prod-migrations"

    # Migration invoker role names (created by aws_lambda module)
    conventional_dev_codebuild_migrations_invoker_name = "${var.app}-dev-codepipeline-migration-invoker"
    conventional_prod_codebuild_migrations_invoker_name = "${var.app}-prod-codepipeline-migration-invoker"

    # CodeDeploy IAM role names (created by aws_lambda module)
    conventional_dev_codedeploy_role_name = "${var.app}-dev-codedeploy"
    conventional_prod_codedeploy_role_name = "${var.app}-prod-codedeploy"

    # Deploy Lambda function names (created by aws_lambda module)
    conventional_dev_deploy_lambda_name = "${var.app}-dev-deploy"
    conventional_prod_deploy_lambda_name = "${var.app}-prod-deploy"

    # Tools cross-account role names (created by aws_lambda module)
    conventional_dev_tools_cross_account_role_name = "${var.app}-dev-tools-access"
    conventional_prod_tools_cross_account_role_name = "${var.app}-prod-tools-access"

    # ECR repository names (created by aws_lambda module)
    conventional_dev_ecr_repository_name = "${var.app}-dev"
    conventional_prod_ecr_repository_name = "${var.app}-prod"

    # Lambda function names (created by aws_lambda module)
    conventional_dev_lambda_function_name = "${var.app}-dev"
    conventional_prod_lambda_function_name = "${var.app}-prod"

    # CodeDeploy application names (created by aws_lambda module)
    conventional_dev_codedeploy_app_name = "${var.app}-dev"
    conventional_prod_codedeploy_app_name = "${var.app}-prod"

    # CodeDeploy deployment group names (created by aws_lambda module)
    conventional_dev_deployment_group_name = "${var.app}-dev"
    conventional_prod_deployment_group_name = "${var.app}-prod"
}
