import boto3
import json
import os
import time
from datetime import datetime, timedelta

codepipeline = boto3.client("codepipeline")
sts = boto3.client("sts")

def report_progress(job_id, context, succeeded=True, msg="ok", pct=100, cont=None, external_id=None):
    """
    Report progress back to CodePipeline with status, percentage, and links.
    """
    args = {
        "jobId": job_id,
        "executionDetails": {
            "summary": msg[:100],
            "percentComplete": pct,
            "externalExecutionId": external_id or context.aws_request_id  # clickable logs link
        }
    }
    if cont:
        args["continuationToken"] = cont        # keep action In Progress
    
    try:
        if succeeded:
            codepipeline.put_job_success_result(**args)
        else:
            codepipeline.put_job_failure_result(
                jobId=job_id,
                failureDetails={
                    "type": "JobFailed",
                    "message": msg[:500]
                }
            )
    except Exception as e:
        error_str = str(e)
        if "InvalidJobStateException" in error_str:
            print(f"Job {job_id} already processed, ignoring: {error_str}")
            return  # Job already completed, this is expected
        else:
            print(f"Unexpected error reporting progress: {error_str}")
            raise

def handler(event, context):
    """
    Deploy from pipeline Lambda that:
    1. Calls deploy lambda in target account
    2. Polls CodeDeploy deployment until completion
    3. Reports success/failure back to CodePipeline
    """
    print(f"Received event: {json.dumps(event)}")
    
    # Extract CodePipeline job data
    job_id = event["CodePipeline.job"]["id"]
    job_data = event["CodePipeline.job"]["data"]
    
    try:
        # Check if this is a continuation from previous invocation
        continuation_token = job_data.get("continuationToken")
        
        if continuation_token:
            # This is a continuation - resume polling deployment
            deployment_data = json.loads(continuation_token)
            return resume_deployment_polling(job_id, context, deployment_data)
        
        # Initial invocation - start deployment
        report_progress(job_id, context, msg="Starting deployment", pct=5)
        
        # Get UserParameters with simplified deployment info
        user_params = job_data.get("actionConfiguration", {}).get("configuration", {}).get("UserParameters", "{}")
        params = json.loads(user_params)
        
        print(f"Deployment parameters: {json.dumps(params)}")
        
        # Extract deployment info
        target_account = params["accountId"]
        target_region = params["region"]
        repository_name = params["repositoryName"]
        cross_account_role_arn = params["crossAccountRoleArn"]
        deploy_lambda_name = params["deployLambdaName"]
        image_tag = params["imageTag"]
        image_digest = params.get("imageDigest", "")
        
        print(f"Calling deploy lambda: {deploy_lambda_name} in account {target_account}")
        
        report_progress(job_id, context, msg=f"Assuming role in {target_account}", pct=10)
        
        # Create synthetic ECR event for deploy lambda
        synthetic_event = {
            "account": target_account,
            "region": target_region,
            "detail": {
                "repository-name": repository_name,
                "image-tag": image_tag,
                "action-type": ["PUSH"],
                "result": ["SUCCESS"]
            }
        }
        
        if image_digest:
            synthetic_event["detail"]["image-digest"] = image_digest
        
        # Assume cross-account role
        assumed_role = sts.assume_role(
            RoleArn=cross_account_role_arn,
            RoleSessionName=f"deploy-from-pipeline-{target_account}"
        )
        
        # Create Lambda client with assumed role credentials
        credentials = assumed_role["Credentials"]
        target_lambda = boto3.client(
            "lambda",
            aws_access_key_id=credentials["AccessKeyId"],
            aws_secret_access_key=credentials["SecretAccessKey"],
            aws_session_token=credentials["SessionToken"],
            region_name=target_region
        )
        
        report_progress(job_id, context, msg=f"Triggering deployment for {image_tag}", pct=30)
        
        # Call deploy lambda in target account
        deploy_response = target_lambda.invoke(
            FunctionName=deploy_lambda_name,
            InvocationType="RequestResponse",
            Payload=json.dumps(synthetic_event)
        )
        
        # Parse response from deploy lambda
        deploy_result = json.loads(deploy_response["Payload"].read())
        
        print(f"Deploy lambda response: {json.dumps(deploy_result)}")
        
        if deploy_response["StatusCode"] != 200:
            raise Exception(f"Deploy lambda failed with status {deploy_response['StatusCode']}: {deploy_result}")
        
        # Check if deploy lambda returned an error
        if "errorType" in deploy_result:
            error_msg = deploy_result.get("errorMessage", "Unknown error")
            raise Exception(f"Deploy lambda failed: {error_msg}")
        
        # Check for expected response format
        if "body" not in deploy_result:
            raise Exception(f"Deploy lambda response missing 'body' field: {deploy_result}")
        
        deploy_body = json.loads(deploy_result["body"])
        deployment_id = deploy_body["deploymentId"]
        
        print(f"Deploy lambda succeeded, deployment ID: {deployment_id}")
        
        # Create deployment console link
        deployment_link = f"https://{target_region}.console.aws.amazon.com/codesuite/codedeploy/deployments/{deployment_id}"
        
        report_progress(job_id, context, msg=f"Deployment {deployment_id} started", pct=40, external_id=deployment_link)
        
        # Create CodeDeploy client with assumed role
        target_codedeploy = boto3.client(
            "codedeploy",
            aws_access_key_id=credentials["AccessKeyId"],
            aws_secret_access_key=credentials["SecretAccessKey"],
            aws_session_token=credentials["SessionToken"],
            region_name=target_region
        )
        
        # Start polling - package data for continuation
        deployment_data = {
            "deploymentId": deployment_id,
            "targetAccount": target_account,
            "targetRegion": target_region,
            "deploymentLink": deployment_link,
            "credentials": {
                "AccessKeyId": credentials["AccessKeyId"],
                "SecretAccessKey": credentials["SecretAccessKey"],
                "SessionToken": credentials["SessionToken"]
            },
            "startTime": datetime.utcnow().isoformat()
        }
        
        # Start initial polling
        return poll_deployment_with_continuation(job_id, context, deployment_data)
        
    except Exception as e:
        print(f"Error in deploy-from-pipeline: {str(e)}")
        
        # Report failure to CodePipeline (use report_progress to avoid duplicate calls)
        try:
            report_progress(job_id, context, succeeded=False, 
                          msg=f"Deploy from pipeline failed: {str(e)}")
        except Exception as report_error:
            print(f"Failed to report error to CodePipeline: {str(report_error)}")
            # If we can't report through report_progress, the job may already be marked as failed
            # Don't raise this error to avoid masking the original error
        
        raise

def resume_deployment_polling(job_id, context, deployment_data):
    """
    Resume polling an existing deployment from continuation token.
    """
    print(f"Resuming deployment polling for {deployment_data['deploymentId']}")
    
    # Recreate CodeDeploy client with stored credentials
    credentials = deployment_data["credentials"]
    codedeploy_client = boto3.client(
        "codedeploy",
        aws_access_key_id=credentials["AccessKeyId"],
        aws_secret_access_key=credentials["SecretAccessKey"],
        aws_session_token=credentials["SessionToken"],
        region_name=deployment_data["targetRegion"]
    )
    
    # Continue polling
    return poll_deployment_with_continuation(job_id, context, deployment_data, codedeploy_client)

def poll_deployment_with_continuation(job_id, context, deployment_data, codedeploy_client=None):
    """
    Poll deployment status with progress reporting and continuation tokens.
    """
    deployment_id = deployment_data["deploymentId"]
    deployment_link = deployment_data["deploymentLink"]
    
    # Create CodeDeploy client if not provided
    if not codedeploy_client:
        credentials = deployment_data["credentials"]
        codedeploy_client = boto3.client(
            "codedeploy",
            aws_access_key_id=credentials["AccessKeyId"],
            aws_secret_access_key=credentials["SecretAccessKey"],
            aws_session_token=credentials["SessionToken"],
            region_name=deployment_data["targetRegion"]
        )
    
    # Calculate elapsed time for progress estimation
    start_time = datetime.fromisoformat(deployment_data["startTime"])
    elapsed_minutes = (datetime.utcnow() - start_time).total_seconds() / 60
    
    try:
        # Get deployment status
        response = codedeploy_client.get_deployment(deploymentId=deployment_id)
        deployment_info = response["deploymentInfo"]
        
        status = deployment_info["status"]
        print(f"Deployment {deployment_id} status: {status}")
        
        # Calculate progress percentage based on status and elapsed time
        if status == "Created":
            progress_pct = 45
            status_msg = "Deployment created, waiting to start"
        elif status == "Queued":
            progress_pct = 50
            status_msg = "Deployment queued for execution"
        elif status == "InProgress":
            # Estimate progress based on elapsed time (typical deployment takes 5-10 minutes)
            estimated_progress = min(85, 55 + (elapsed_minutes * 6))  # 6% per minute, max 85%
            progress_pct = int(estimated_progress)
            status_msg = f"Deployment in progress ({elapsed_minutes:.1f}m elapsed)"
        elif status == "Succeeded":
            progress_pct = 100
            status_msg = "Deployment completed successfully"
            
            # Report final success
            report_progress(job_id, context, succeeded=True, msg=status_msg, 
                          pct=progress_pct, external_id=deployment_link)
            return
        elif status in ["Failed", "Stopped"]:
            # Get error information
            error_info = deployment_info.get("errorInformation", {})
            error_message = error_info.get("message", f"Deployment {status}")
            
            # Report failure
            report_progress(job_id, context, succeeded=False, 
                          msg=f"Deployment {status}: {error_message}")
            return
        else:
            # Unknown status
            progress_pct = 60
            status_msg = f"Deployment status: {status}"
        
        # Check if Lambda is about to timeout (leave 90 seconds buffer)
        remaining_time = context.get_remaining_time_in_millis() / 1000
        if remaining_time < 90:
            print(f"Lambda timeout approaching ({remaining_time}s remaining), using continuation")
            
            # Report progress with continuation token
            continuation_token = json.dumps(deployment_data)
            report_progress(job_id, context, succeeded=True, msg=status_msg, 
                          pct=progress_pct, cont=continuation_token, external_id=deployment_link)
            return
        
        # Report progress without continuation (keep polling)
        report_progress(job_id, context, succeeded=True, msg=status_msg, 
                      pct=progress_pct, external_id=deployment_link)
        
        # Sleep before next poll
        time.sleep(10)
        
        # Continue polling
        return poll_deployment_with_continuation(job_id, context, deployment_data, codedeploy_client)
        
    except Exception as e:
        print(f"Error polling deployment status: {str(e)}")
        report_progress(job_id, context, succeeded=False, 
                      msg=f"Error polling deployment: {str(e)}")
        return
