# Parameter Store entries for sensitive terraform variables
locals {
    parameter_prefix = "/${var.org}/${var.app}/${var.env}/terraform-lambda"
    # Extract only the keys from the sensitive map - these are safe to expose
    tfvars_sensitive_keys = toset(keys(nonsensitive(var.tfvars_sensitive)))
}

# Store sensitive terraform variables in Parameter Store
resource "aws_ssm_parameter" "tfvars_sensitive" {
    for_each = local.tfvars_sensitive_keys
    
    name  = "${local.parameter_prefix}/${each.value}"
    type  = "SecureString"
    value = var.tfvars_sensitive[each.value]  # Secret value looked up here
    
    tags = local.tags
}