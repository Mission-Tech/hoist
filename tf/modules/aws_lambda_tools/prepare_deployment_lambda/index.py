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
            "timestamp": datetime.utcnow().isoformat()
        }

        # Create and upload source.zip (just metadata, no appspec needed)
        create_and_upload_artifact(deployment_metadata)

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
                "prodImageUri": prod_image_uri
            })
        }

    except Exception as e:
        print(f"Error preparing deployment: {str(e)}")
        raise

def create_and_upload_artifact(metadata):
    """Create dev and prod artifacts with just metadata (no appspec needed)."""
    with tempfile.TemporaryDirectory() as temp_dir:
        bucket = os.environ["ARTIFACTS_BUCKET"]

        # Create source-dev.zip with just metadata
        dev_zip_path = os.path.join(temp_dir, "source-dev.zip")
        with zipfile.ZipFile(dev_zip_path, "w") as zipf:
            zipf.writestr("deployment-metadata.json", json.dumps(metadata, indent=2))

        # Create source-prod.zip with just metadata  
        prod_zip_path = os.path.join(temp_dir, "source-prod.zip")
        with zipfile.ZipFile(prod_zip_path, "w") as zipf:
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
