import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any, Optional

codedeploy = boto3.client('codedeploy')
ecr = boto3.client('ecr')
lambda_client = boto3.client('lambda')

def handler(event, context):
    """
    Promote Lambda function from dev to prod by:
    1. Validating latest dev deployment succeeded
    2. Verifying container SHA matches between accounts
    3. Triggering deployment in prod with same container
    """
    print(f"Received event: {json.dumps(event)}")
    
    try:
        # Environment variables
        app_name = os.environ['APP_NAME']
        env_name = os.environ['ENV_NAME']
        dev_account_id = os.environ['DEV_ACCOUNT_ID']
        manual_deploy_function = os.environ['MANUAL_DEPLOY_FUNCTION_NAME']
        
        # Parse input (could come from GitHub action or manual trigger)
        release_tag = event.get('release_tag')
        if not release_tag:
            raise ValueError("Missing 'release_tag' in event")
        
        print(f"Promoting release {release_tag} from dev account {dev_account_id}")
        
        # Step 1: Get latest successful deployment from dev account
        dev_deployment_info = get_latest_successful_dev_deployment(
            app_name, env_name, dev_account_id
        )
        
        if not dev_deployment_info:
            raise ValueError(f"No successful deployment found in dev account {dev_account_id}")
        
        dev_image_uri = dev_deployment_info['image_uri']
        dev_image_tag = dev_deployment_info['image_tag']
        dev_image_sha = dev_deployment_info['image_sha']
        
        print(f"Latest successful dev deployment: {dev_image_uri}")
        print(f"Dev image SHA: {dev_image_sha}")
        
        # Step 2: Verify the same container exists in prod ECR
        prod_image_uri = f"{context.invoked_function_arn.split(':')[4]}.dkr.ecr.{os.environ['AWS_REGION']}.amazonaws.com/{app_name}-{env_name}:{dev_image_tag}"
        prod_image_sha = get_ecr_image_sha(f"{app_name}-{env_name}", dev_image_tag)
        
        if not prod_image_sha:
            raise ValueError(f"Image {dev_image_tag} not found in prod ECR repository")
        
        if dev_image_sha != prod_image_sha:
            raise ValueError(f"Image SHA mismatch! Dev: {dev_image_sha}, Prod: {prod_image_sha}")
        
        print(f"Container SHA verified: {prod_image_sha}")
        
        # Step 3: Trigger manual deployment in prod
        manual_deploy_event = {
            "image_tag": dev_image_tag,
            "description": f"Promoted from dev via release {release_tag}",
            "release_tag": release_tag
        }
        
        print(f"Triggering manual deployment with: {manual_deploy_event}")
        
        response = lambda_client.invoke(
            FunctionName=manual_deploy_function,
            InvocationType='Event',  # Async
            Payload=json.dumps(manual_deploy_event)
        )
        
        print(f"Manual deployment triggered successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully promoted {release_tag} from dev to prod',
                'dev_deployment': dev_deployment_info,
                'prod_image_uri': prod_image_uri,
                'image_sha': prod_image_sha
            })
        }
        
    except Exception as e:
        print(f"Error promoting deployment: {str(e)}")
        raise


def get_latest_successful_dev_deployment(app_name: str, env_name: str, dev_account_id: str) -> Optional[Dict[str, Any]]:
    """
    Get information about the latest successful deployment in dev account.
    Uses cross-account role to access dev CodeDeploy.
    """
    # Assume cross-account role to access dev
    sts = boto3.client('sts')
    dev_role_arn = f"arn:aws:iam::{dev_account_id}:role/{app_name}-{env_name}-cross-account-read"
    
    try:
        assumed_role = sts.assume_role(
            RoleArn=dev_role_arn,
            RoleSessionName=f"promote-{app_name}-{env_name}"
        )
        
        # Create dev account clients
        dev_credentials = assumed_role['Credentials']
        dev_codedeploy = boto3.client(
            'codedeploy',
            aws_access_key_id=dev_credentials['AccessKeyId'],
            aws_secret_access_key=dev_credentials['SecretAccessKey'],
            aws_session_token=dev_credentials['SessionToken']
        )
        
        dev_s3 = boto3.client(
            's3',
            aws_access_key_id=dev_credentials['AccessKeyId'],
            aws_secret_access_key=dev_credentials['SecretAccessKey'],
            aws_session_token=dev_credentials['SessionToken']
        )
        
        # List deployments for the application
        deployments_response = dev_codedeploy.list_deployments(
            applicationName=f"{app_name}-{env_name}",
            deploymentGroupName=f"{app_name}-{env_name}",
            includeOnlyStatuses=['Succeeded']
        )
        
        if not deployments_response['deployments']:
            return None
        
        # Get the most recent successful deployment
        latest_deployment_id = deployments_response['deployments'][0]
        
        deployment_info = dev_codedeploy.get_deployment(
            deploymentId=latest_deployment_id
        )
        
        # Extract S3 location of AppSpec
        revision = deployment_info['deploymentInfo']['revision']
        if revision['revisionType'] != 'S3':
            raise ValueError("Expected S3 revision type for AppSpec")
        
        s3_location = revision['s3Location']
        bucket = s3_location['bucket']
        key = s3_location['key']
        
        # Download and parse AppSpec to get image info
        appspec_obj = dev_s3.get_object(Bucket=bucket, Key=key)
        appspec_content = json.loads(appspec_obj['Body'].read().decode('utf-8'))
        
        # Extract target version from AppSpec
        target_version = appspec_content['Resources'][0]['TargetService']['Properties']['TargetVersion']
        
        # Get Lambda function info to extract image URI
        dev_lambda = boto3.client(
            'lambda',
            aws_access_key_id=dev_credentials['AccessKeyId'],
            aws_secret_access_key=dev_credentials['SecretAccessKey'],
            aws_session_token=dev_credentials['SessionToken']
        )
        
        function_info = dev_lambda.get_function(
            FunctionName=f"{app_name}-{env_name}",
            Qualifier=target_version
        )
        
        image_uri = function_info['Code']['ImageUri']
        
        # Parse image tag and SHA from URI
        if '@sha256:' in image_uri:
            # Format: repo:tag@sha256:hash
            base_uri, sha_part = image_uri.split('@sha256:')
            image_sha = f"sha256:{sha_part}"
            if ':' in base_uri:
                image_tag = base_uri.split(':')[-1]
            else:
                image_tag = 'latest'
        else:
            # Format: repo:tag - need to get SHA separately
            image_tag = image_uri.split(':')[-1] if ':' in image_uri else 'latest'
            
            # Get SHA from ECR
            repo_name = f"{app_name}-{env_name}"
            dev_ecr = boto3.client(
                'ecr',
                aws_access_key_id=dev_credentials['AccessKeyId'],
                aws_secret_access_key=dev_credentials['SecretAccessKey'],
                aws_session_token=dev_credentials['SessionToken']
            )
            
            image_sha = get_ecr_image_sha_with_client(dev_ecr, repo_name, image_tag)
        
        return {
            'deployment_id': latest_deployment_id,
            'image_uri': image_uri,
            'image_tag': image_tag,
            'image_sha': image_sha,
            'target_version': target_version
        }
        
    except Exception as e:
        print(f"Error accessing dev account: {str(e)}")
        raise


def get_ecr_image_sha(repository_name: str, image_tag: str) -> Optional[str]:
    """Get the SHA256 digest for an ECR image tag in current account"""
    return get_ecr_image_sha_with_client(ecr, repository_name, image_tag)


def get_ecr_image_sha_with_client(ecr_client, repository_name: str, image_tag: str) -> Optional[str]:
    """Get the SHA256 digest for an ECR image tag using provided ECR client"""
    try:
        response = ecr_client.describe_images(
            repositoryName=repository_name,
            imageIds=[{'imageTag': image_tag}]
        )
        
        if response['imageDetails']:
            return response['imageDetails'][0]['imageDigest']
        
        return None
        
    except Exception as e:
        print(f"Error getting ECR image SHA: {str(e)}")
        return None