# Conventional names used by this module

locals {
    # S3 bucket name in tools account that stores pipeline artifacts
    conventional_tools_pipeline_artifacts_bucket = "${var.org}-${var.app}-tools-${var.tools_account_id}-pipeline"
    
    # KMS key alias created by coreinfra in tools account
    conventional_pipeline_kms_key_alias = "alias/${var.org}-coreinfra-tools-pipeline-artifacts"
    
    # VPC and subnet names created by coreinfra
    conventional_coreinfra_vpc_name = "${var.org}-${var.env}"
    conventional_coreinfra_public_subnets = [
        "${var.org}-${var.env}-public-0",
        "${var.org}-${var.env}-public-1",
        "${var.org}-${var.env}-public-2"
    ]
}