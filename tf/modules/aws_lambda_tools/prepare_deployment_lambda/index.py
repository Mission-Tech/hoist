import boto3
import json
import os
import tempfile
import zipfile
from datetime import datetime

s3 = boto3.client("s3")
codepipeline = boto3.client("codepipeline")
sts = boto3.client("sts")

def handler(event, context):
    """
    Prepare deployment artifacts from ECR push event.
    Updates Lambda functions in both dev and prod accounts, publishes versions,
    and creates proper AppSpec files with CurrentVersion → TargetVersion.
    """
    print(f"Received event: {json.dumps(event)}")

    # Extract ECR event details
    detail = event["detail"]
    repo = detail["repository-name"]
    tag = detail.get("image-tag", "latest")
    digest = detail.get("image-digest")
    account_id = event["account"]
    region = event["region"]

    # Construct the image URI
    if digest:
        image_uri = f"{account_id}.dkr.ecr.{region}.amazonaws.com/{repo}@{digest}"
    else:
        image_uri = f"{account_id}.dkr.ecr.{region}.amazonaws.com/{repo}:{tag}"

    print(f"Processing ECR push from dev: {image_uri}")

    # Get function names and role ARNs
    dev_lambda_function = os.environ["DEV_LAMBDA_FUNCTION"]
    prod_lambda_function = os.environ["PROD_LAMBDA_FUNCTION"]
    dev_role_arn = os.environ["DEV_CROSS_ACCOUNT_ROLE"]
    prod_role_arn = os.environ["PROD_CROSS_ACCOUNT_ROLE"]
    dev_account_id = os.environ["DEV_ACCOUNT_ID"]
    prod_account_id = os.environ["PROD_ACCOUNT_ID"]
    dev_region = os.environ["DEV_REGION"]
    prod_region = os.environ["PROD_REGION"]

    # Construct repository names for each environment
    app_name = os.environ["APP_NAME"]
    dev_repo_name = f"{app_name}-dev"
    prod_repo_name = f"{app_name}-prod"

    # Construct ECR URIs for each account
    if digest:
        dev_image_uri = f"{dev_account_id}.dkr.ecr.{dev_region}.amazonaws.com/{dev_repo_name}@{digest}"
        prod_image_uri = f"{prod_account_id}.dkr.ecr.{prod_region}.amazonaws.com/{prod_repo_name}@{digest}"
    else:
        dev_image_uri = f"{dev_account_id}.dkr.ecr.{dev_region}.amazonaws.com/{dev_repo_name}:{tag}"
        prod_image_uri = f"{prod_account_id}.dkr.ecr.{prod_region}.amazonaws.com/{prod_repo_name}:{tag}"

    try:
        # Update dev Lambda function and get version info
        dev_info = update_lambda_function(dev_role_arn, dev_lambda_function, dev_image_uri, "dev")

        # Update prod Lambda function and get version info  
        prod_info = update_lambda_function(prod_role_arn, prod_lambda_function, prod_image_uri, "prod")

        # Create AppSpec files with proper version transitions
        dev_appspec = create_appspec(dev_lambda_function, dev_info["current_version"], dev_info["new_version"])
        prod_appspec = create_appspec(prod_lambda_function, prod_info["current_version"], prod_info["new_version"])

        # Create deployment metadata
        deployment_metadata = {
            "sourceImageUri": image_uri,
            "devImageUri": dev_image_uri,
            "prodImageUri": prod_image_uri,
            "imageTag": tag,
            "digest": digest,
            "repository": repo,
            "sourceAccount": account_id,
            "region": region,
            "timestamp": datetime.utcnow().isoformat(),
            "devVersion": dev_info["new_version"],
            "prodVersion": prod_info["new_version"]
        }

        # Create and upload source.zip
        create_and_upload_artifact(dev_appspec, prod_appspec, deployment_metadata)

        # Start pipeline execution
        pipeline_name = os.environ["PIPELINE_NAME"]
        print(f"Starting pipeline: {pipeline_name}")

        response = codepipeline.start_pipeline_execution(
            name=pipeline_name
        )

        execution_id = response["pipelineExecutionId"]
        print(f"Started pipeline execution: {execution_id}")

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": f"Deployment pipeline started for {image_uri}",
                "pipelineExecutionId": execution_id,
                "sourceImageUri": image_uri,
                "devImageUri": dev_image_uri,
                "prodImageUri": prod_image_uri,
                "devVersion": dev_info["new_version"],
                "prodVersion": prod_info["new_version"]
            })
        }

    except Exception as e:
        print(f"Error preparing deployment: {str(e)}")
        raise

def update_lambda_function(role_arn, function_name, image_uri, env_name):
    """Update Lambda function with new image and publish version."""
    # Assume cross-account role
    external_id = f"{os.environ.get('APP_NAME', 'app')}-{env_name}-tools"

    print(f"Assuming role for {env_name}: {role_arn}")
    assumed_role = sts.assume_role(
        RoleArn=role_arn,
        RoleSessionName=f"tools-prepare-deployment-{env_name}",
        ExternalId=external_id
    )

    # Create Lambda client with assumed role credentials
    credentials = assumed_role["Credentials"]
    lambda_client = boto3.client(
        "lambda",
        aws_access_key_id=credentials["AccessKeyId"],
        aws_secret_access_key=credentials["SecretAccessKey"],
        aws_session_token=credentials["SessionToken"],
        region_name=os.environ.get(f"{env_name.upper()}_REGION", "us-east-1")
    )

    # Get current version that the alias points to
    try:
        alias_response = lambda_client.get_alias(
            FunctionName=function_name,
            Name='live'
        )
        current_version = alias_response['FunctionVersion']
        print(f"{env_name} current alias version: {current_version}")
    except Exception as e:
        print(f"Error getting {env_name} alias: {str(e)}")
        raise ValueError(f"Could not get 'live' alias for function {function_name}. Make sure it exists.")

    # Update the Lambda function with new image
    print(f"Updating {env_name} Lambda function {function_name} with image: {image_uri}")
    lambda_client.update_function_code(
        FunctionName=function_name,
        ImageUri=image_uri
    )

    # Wait for the update to complete
    waiter = lambda_client.get_waiter('function_updated')
    waiter.wait(FunctionName=function_name)

    # Publish a new version
    version_response = lambda_client.publish_version(
        FunctionName=function_name,
        Description=f'Deployed from {image_uri}'
    )
    new_version = version_response['Version']
    print(f"Published {env_name} Lambda version: {new_version}")

    return {
        "current_version": current_version,
        "new_version": new_version
    }

def create_appspec(function_name, current_version, target_version):
    """Create AppSpec YAML content for CodeDeploy."""
    return f"""version: 0.0
Resources:
  - TargetService:
      Type: AWS::Lambda::Function
      Properties:
        Name: {function_name}
        Alias: live
        CurrentVersion: "{current_version}"
        TargetVersion: "{target_version}"
"""

def create_and_upload_artifact(dev_appspec, prod_appspec, metadata):
    """Create separate dev and prod artifacts with AppSpec in root and upload to S3."""
    with tempfile.TemporaryDirectory() as temp_dir:
        bucket = os.environ["ARTIFACTS_BUCKET"]

        # Create source-dev.zip with AppSpec in root
        dev_zip_path = os.path.join(temp_dir, "source-dev.zip")
        with zipfile.ZipFile(dev_zip_path, "w") as zipf:
            # Write dev AppSpec directly to root as appspec.yml
            zipf.writestr("appspec.yml", dev_appspec)

            # Include metadata
            zipf.writestr("deployment-metadata.json", json.dumps(metadata, indent=2))

        # Create source-prod.zip with AppSpec in root
        prod_zip_path = os.path.join(temp_dir, "source-prod.zip")
        with zipfile.ZipFile(prod_zip_path, "w") as zipf:
            # Write prod AppSpec directly to root as appspec.yml
            zipf.writestr("appspec.yml", prod_appspec)

            # Include metadata
            zipf.writestr("deployment-metadata.json", json.dumps(metadata, indent=2))

        # Upload source-dev.zip
        print(f"Uploading source-dev.zip to s3://{bucket}/source-dev.zip")
        with open(dev_zip_path, "rb") as f:
            s3.put_object(
                Bucket=bucket,
                Key="source-dev.zip",
                Body=f,
                Metadata={
                    "image-uri": metadata["devImageUri"],
                    "timestamp": metadata["timestamp"],
                    "environment": "dev"
                }
            )

        # Upload source-prod.zip
        print(f"Uploading source-prod.zip to s3://{bucket}/source-prod.zip")
        with open(prod_zip_path, "rb") as f:
            s3.put_object(
                Bucket=bucket,
                Key="source-prod.zip",
                Body=f,
                Metadata={
                    "image-uri": metadata["prodImageUri"],
                    "timestamp": metadata["timestamp"],
                    "environment": "prod"
                }
            )
