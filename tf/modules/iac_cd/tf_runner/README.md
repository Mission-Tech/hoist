# tf_runner

The tofu plan/apply runner per-account

## Bootstrap Process

The tf_runner module creates a CodeBuild-based CI/CD pipeline for Terraform. Here's how variables are handled during the initial bootstrap and subsequent runs:

### First Apply (Local)

On the **first** terraform apply (run locally), you must provide all terraform variables to this module:

- **Non-sensitive variables** via `tfvars` map → These get burned into the CodeBuild job as `TF_VAR_*` environment variables (see `codebuild_terraform_apply.tf:23-29`)
- **Sensitive variables** via `tfvars_sensitive` map → These get stored in SSM Parameter Store at `/<org>/<app>/<env>/tf_runner/*` (see `parameter_store.tf`)

Example usage:
```hcl
module "tf_runner" {
  source = "github.com/Mission-Tech/hoist//tf/modules/iac_cd/tf_runner"

  # These get burned into CodeBuild as TF_VAR_* environment variables
  tfvars = {
    github_org = "mission-tech"
    aws_region = "us-east-1"
  }

  # These get stored in SSM Parameter Store for secure access
  tfvars_sensitive = {
    dev_account_id  = "123456789012"
    prod_account_id = "987654321098"
  }
}
```

### Subsequent Runs (CI/CD)

From that point onward, the CodeBuild job automatically has access to both:
1. **Non-sensitive variables** - Already baked into the CodeBuild environment configuration
2. **Sensitive variables** - Pulled from SSM Parameter Store at runtime (see `buildspec_plan.yml:25-46`)

### Local Development After Bootstrap

For running terraform locally after the initial bootstrap, you'll need to provide the same variables. Rather than manually managing them, use the helper script from the hoist repository:

```bash
# From your terraform directory
terraform plan $(../hoist/scripts/ssm-to-tfvars.sh missiontech myapp prod)
terraform apply $(../hoist/scripts/ssm-to-tfvars.sh missiontech myapp prod)
```

The script pulls sensitive variables from SSM Parameter Store and passes them as `-var` flags, without writing secrets to disk or polluting your shell environment
