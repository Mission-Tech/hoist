# KMS Grants for cross-account CodeBuild access to pipeline artifacts
# This allows the CodeBuild roles in this account to decrypt the KMS key in the tools account

# Read the KMS key ARN from parameter store only if not provided as variable
# This allows coreinfra to pass it directly (avoiding circular dependency)
# while apps like gometheus can read from parameter store
data "aws_ssm_parameter" "pipeline_artifacts_kms_key_arn" {
  count = var.pipeline_artifacts_kms_key_arn == null ? 1 : 0
  name  = "/coreinfra/shared/pipeline_artifacts_kms_key_arn"
}

locals {
  kms_key_arn = var.pipeline_artifacts_kms_key_arn != null ? var.pipeline_artifacts_kms_key_arn : data.aws_ssm_parameter.pipeline_artifacts_kms_key_arn[0].value
}

# Grant for terraform-plan CodeBuild role
resource "aws_kms_grant" "codebuild_plan" {
  name              = "${var.org}-${var.app}-${var.env}-codebuild-terraform-plan"
  key_id            = local.kms_key_arn
  grantee_principal = aws_iam_role.codebuild_terraform_plan.arn
  
  operations = [
    "Decrypt",
    "Encrypt",
    "DescribeKey",
    "GenerateDataKey"
  ]
  
  # Allow the role to retire its own grant (cleanup)
  retiring_principal = aws_iam_role.codebuild_terraform_plan.arn
}

# Grant for terraform-apply CodeBuild role
resource "aws_kms_grant" "codebuild_apply" {
  name              = "${var.org}-${var.app}-${var.env}-codebuild-terraform-apply"
  key_id            = local.kms_key_arn
  grantee_principal = aws_iam_role.codebuild_terraform_apply.arn
  
  operations = [
    "Decrypt",
    "Encrypt",
    "DescribeKey",
    "GenerateDataKey"
  ]
  
  # Allow the role to retire its own grant (cleanup)
  retiring_principal = aws_iam_role.codebuild_terraform_apply.arn
}

# Note: No separate grant needed for terraform-apply-auto
# It reuses the same IAM role as terraform-apply (see codebuild_terraform_apply_auto.tf:7)
