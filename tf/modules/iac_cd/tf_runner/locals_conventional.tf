# Conventional names used by this module

locals {
    # S3 bucket name in tools account that stores pipeline artifacts
    conventional_tools_pipeline_artifacts_bucket = "${var.org}-${var.app}-tools-${var.tools_account_id}-pipeline"
    
    # KMS key alias created by coreinfra in tools account
    conventional_pipeline_kms_key_alias = "alias/${var.org}-coreinfra-tools-pipeline-artifacts"
}