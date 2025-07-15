import boto3
import json
import os
import tempfile
import zipfile
from urllib.parse import urlparse

codepipeline = boto3.client("codepipeline")
s3 = boto3.client("s3")
sts = boto3.client("sts")

def handler(event, context):
    """
    Sync Lambda function code from ECR image.
    Reads deployment metadata from artifact and updates target Lambda function.
    """
    print(f"Received CodePipeline event: {json.dumps(event)}")
    
    # Extract CodePipeline job data
    job_id = event["CodePipeline.job"]["id"]
    job_data = event["CodePipeline.job"]["data"]
    
    try:
        # Get input artifacts
        input_artifacts = job_data["inputArtifacts"]
        if not input_artifacts:
            raise ValueError("No input artifacts provided")
        
        artifact = input_artifacts[0]
        location = artifact["location"]["s3Location"]
        bucket = location["bucketName"]
        key = location["objectKey"]
        
        print(f"Processing artifact: s3://{bucket}/{key}")
        
        # Download and extract the artifact
        with tempfile.TemporaryDirectory() as temp_dir:
            zip_path = os.path.join(temp_dir, "artifact.zip")
            
            # Download artifact
            s3.download_file(bucket, key, zip_path)
            
            # Extract and read metadata
            with zipfile.ZipFile(zip_path, "r") as zipf:
                metadata_content = zipf.read("deployment-metadata.json")
                metadata = json.loads(metadata_content)
        
        print(f"Deployment metadata: {json.dumps(metadata)}")
        
        # Determine target environment from job user parameters
        user_params = job_data.get("actionConfiguration", {}).get("configuration", {})
        environment = user_params.get("UserParameters", "").strip()
        
        if environment == "dev":
            target_account_id = os.environ["DEV_ACCOUNT_ID"]
            target_region = os.environ["DEV_REGION"]
            target_function = os.environ["DEV_LAMBDA_FUNCTION"]
            cross_account_role = os.environ["DEV_CROSS_ACCOUNT_ROLE"]
            image_uri = metadata["devImageUri"]
        elif environment == "prod":
            target_account_id = os.environ["PROD_ACCOUNT_ID"]
            target_region = os.environ["PROD_REGION"]
            target_function = os.environ["PROD_LAMBDA_FUNCTION"]
            cross_account_role = os.environ["PROD_CROSS_ACCOUNT_ROLE"]
            image_uri = metadata["prodImageUri"]
        else:
            raise ValueError(f"Invalid environment: {environment}. Must be 'dev' or 'prod'")
        
        print(f"Updating {environment} Lambda function {target_function} with image: {image_uri}")
        
        # Assume cross-account role
        external_id = f"{os.environ.get('APP_NAME', 'app')}-{environment}-tools"
        assumed_role = sts.assume_role(
            RoleArn=cross_account_role,
            RoleSessionName=f"tools-sync-image-{environment}",
            ExternalId=external_id
        )
        
        # Create Lambda client with assumed role credentials
        credentials = assumed_role["Credentials"]
        lambda_client = boto3.client(
            "lambda",
            aws_access_key_id=credentials["AccessKeyId"],
            aws_secret_access_key=credentials["SecretAccessKey"],
            aws_session_token=credentials["SessionToken"],
            region_name=target_region
        )
        
        # Update Lambda function code to sync $LATEST with the ECR image
        print(f"Updating function code for {target_function}")
        lambda_client.update_function_code(
            FunctionName=target_function,
            ImageUri=image_uri
        )
        
        # Wait for the update to complete
        waiter = lambda_client.get_waiter('function_updated')
        waiter.wait(FunctionName=target_function)
        
        print(f"Successfully updated {environment} Lambda function $LATEST to {image_uri}")
        
        # Signal success to CodePipeline
        codepipeline.put_job_success_result(jobId=job_id)
        
        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": f"Successfully synced {environment} Lambda function with {image_uri}",
                "environment": environment,
                "function": target_function,
                "imageUri": image_uri
            })
        }
        
    except Exception as e:
        print(f"Error syncing image: {str(e)}")
        
        # Signal failure to CodePipeline
        codepipeline.put_job_failure_result(
            jobId=job_id,
            failureDetails={
                "message": str(e),
                "type": "JobFailed"
            }
        )
        
        raise