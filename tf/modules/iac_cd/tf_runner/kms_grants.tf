# KMS Grants for cross-account CodeBuild access to pipeline artifacts
# This allows the CodeBuild roles in this account to decrypt the KMS key in the tools account

# Look up the KMS key ARN from parameter store (set by coreinfra in tools account)
data "aws_ssm_parameter" "pipeline_artifacts_kms_key_arn" {
  name = "/coreinfra/shared/pipeline_artifacts_kms_key_arn"
}

# Grant for terraform-plan CodeBuild role
resource "aws_kms_grant" "codebuild_plan" {
  name              = "${var.org}-${var.app}-${var.env}-codebuild-terraform-plan"
  key_id            = data.aws_ssm_parameter.pipeline_artifacts_kms_key_arn.value
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
  key_id            = data.aws_ssm_parameter.pipeline_artifacts_kms_key_arn.value
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

# Grant for terraform-apply-auto CodeBuild role (if enabled)
resource "aws_kms_grant" "codebuild_apply_auto" {
  count = var.enable_auto_apply ? 1 : 0

  name              = "${var.org}-${var.app}-${var.env}-codebuild-terraform-apply-auto"
  key_id            = data.aws_ssm_parameter.pipeline_artifacts_kms_key_arn.value
  grantee_principal = aws_iam_role.codebuild_terraform_apply_auto[0].arn
  
  operations = [
    "Decrypt",
    "Encrypt",
    "DescribeKey",
    "GenerateDataKey"
  ]
  
  # Allow the role to retire its own grant (cleanup)
  retiring_principal = aws_iam_role.codebuild_terraform_apply_auto[0].arn
}
