# Inputs that are created by other terraform modules that we're using 
# because the names are conventional.

locals {
    # Created by coreinfra
    conventional_slack_cd_webhook_url_parameterstore_path = "/coreinfra/shared/slack_cd_webhook_url"
}
