# Inputs that are created by other terraform modules that we're using 
# because the names are conventional.

locals {
    # Created by coreinfra (github.com/mission-tech/coreinfra
    conventional_github_oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}
