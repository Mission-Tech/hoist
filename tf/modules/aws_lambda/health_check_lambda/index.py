import json
import os
import boto3

# Initialize clients
lambda_client = boto3.client('lambda')
codedeploy = boto3.client('codedeploy')
s3_client = boto3.client('s3')

def handler(event, context):
    """
    BeforeAllowTraffic hook to verify the new Lambda version is healthy
    before routing traffic to it.
    """
    print(f"Received event: {json.dumps(event)}")
    
    deployment_id = event['DeploymentId']
    lifecycle_event_hook_execution_id = event['LifecycleEventHookExecutionId']
    
    try:
        # Get the function name from environment variables
        function_name = os.environ['FUNCTION_NAME']
        
        # Extract the version being deployed from the event
        print(f"Checking health of function: {function_name}")
        
        # Get the target version from the deployment
        target_version = event.get('TargetVersion')
        
        if not target_version:
            # Get target version from S3-stored AppSpec
            print("Target version not in event, getting from S3 AppSpec")
            
            try:
                # Get deployment details
                deployment_response = codedeploy.get_deployment(deploymentId=deployment_id)
                print(f"Deployment response: {json.dumps(deployment_response, default=str)}")
                
                # Extract S3 location from deployment
                revision = deployment_response['deploymentInfo']['revision']
                if revision['revisionType'] == 'S3':
                    s3_location = revision['s3Location']
                    bucket = s3_location['bucket']
                    key = s3_location['key']
                    
                    print(f"Reading AppSpec from S3: s3://{bucket}/{key}")
                    
                    # Read AppSpec from S3
                    response = s3_client.get_object(Bucket=bucket, Key=key)
                    appspec_content = response['Body'].read().decode('utf-8')
                    app_spec = json.loads(appspec_content)
                    
                    print(f"AppSpec content: {json.dumps(app_spec, indent=2)}")
                    
                    # Extract target version
                    target_version = app_spec['Resources'][0]['TargetService']['Properties']['TargetVersion']
                    print(f"Extracted target version: {target_version}")
                else:
                    raise ValueError(f"Unsupported revision type: {revision['revisionType']}")
                    
            except Exception as e:
                print(f"Error reading AppSpec from S3: {e}")
                raise
        
        print(f"Testing version: {target_version}")
        
        # Invoke the specific version of the Lambda function
        invoke_response = lambda_client.invoke(
            FunctionName=function_name,
            Qualifier=target_version,
            InvocationType='RequestResponse',
            Payload=json.dumps({
                "rawPath": "/health",
                "requestContext": {
                    "http": {
                        "method": "GET"
                    }
                }
            })
        )
        
        # Check if the function returned successfully (200 status code)
        if invoke_response.get('StatusCode') == 200:
            print("Health check passed!")
            codedeploy.put_lifecycle_event_hook_execution_status(
                deploymentId=deployment_id,
                lifecycleEventHookExecutionId=lifecycle_event_hook_execution_id,
                status='Succeeded'
            )
            return {
                'statusCode': 200,
                'body': json.dumps('Health check passed')
            }
        else:
            print(f"Health check failed with status code: {invoke_response.get('StatusCode')}")
            codedeploy.put_lifecycle_event_hook_execution_status(
                deploymentId=deployment_id,
                lifecycleEventHookExecutionId=lifecycle_event_hook_execution_id,
                status='Failed'
            )
            return {
                'statusCode': 500,
                'body': json.dumps('Health check failed')
            }
        
    except Exception as e:
        print(f"Error during health check: {str(e)}")
        codedeploy.put_lifecycle_event_hook_execution_status(
            deploymentId=deployment_id,
            lifecycleEventHookExecutionId=lifecycle_event_hook_execution_id,
            status='Failed'
        )
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }