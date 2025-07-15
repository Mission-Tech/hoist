import boto3
import json
import os
from datetime import datetime

codepipeline = boto3.client("codepipeline")

def handler(event, context):
    """
    Start deployment pipeline from ECR push event.
    Extracts image tag/digest from ECR event and starts pipeline with variables.
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
        # Start pipeline execution with variables
        pipeline_name = os.environ["PIPELINE_NAME"]
        print(f"Starting pipeline: {pipeline_name}")

        response = codepipeline.start_pipeline_execution(
            name=pipeline_name,
            variables=[
                {
                    'name': 'DEV_IMAGE_TAG',
                    'value': tag
                },
                {
                    'name': 'PROD_IMAGE_TAG', 
                    'value': tag
                },
                {
                    'name': 'DEV_IMAGE_DIGEST',
                    'value': digest or ''
                },
                {
                    'name': 'PROD_IMAGE_DIGEST',
                    'value': digest or ''
                }
            ]
        )

        execution_id = response["pipelineExecutionId"]
        print(f"Started pipeline execution: {execution_id}")

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": f"Deployment pipeline started for {image_uri}",
                "pipelineExecutionId": execution_id,
                "imageTag": tag,
                "imageDigest": digest
            })
        }

    except Exception as e:
        print(f"Error preparing deployment: {str(e)}")
        raise
