import json
import boto3
import os

codedeploy = boto3.client('codedeploy')
lambda_client = boto3.client('lambda')

def handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    # Parse ECR push event
    detail = event['detail']
    repository_name = detail['repository-name']
    
    # Require image-tag to be present
    if 'image-tag' not in detail:
        raise ValueError("Missing 'image-tag' in ECR event detail")
    
    image_tag = detail['image-tag']
    image_uri = f"{event['account']}.dkr.ecr.{event['region']}.amazonaws.com/{repository_name}:{image_tag}"
    
    # Get Lambda function configuration
    function_name = os.environ['LAMBDA_FUNCTION_NAME']
    
    try:
        # First, update the Lambda function with the new image
        print(f"Updating Lambda function {function_name} with image: {image_uri}")
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
        print(f"Published Lambda version: {new_version}")
        
        # Get the current version that the alias points to
        try:
            alias_response = lambda_client.get_alias(
                FunctionName=function_name,
                Name='live'
            )
            current_version = alias_response['FunctionVersion']
            print(f"Current alias version: {current_version}")
        except Exception as e:
            print(f"Error getting alias: {str(e)}")
            raise ValueError(f"Could not get 'live' alias for function {function_name}. Make sure it exists.")
        
        # Create CodeDeploy deployment
        response = codedeploy.create_deployment(
            applicationName=os.environ['CODEDEPLOY_APP_NAME'],
            deploymentGroupName=os.environ['DEPLOYMENT_GROUP_NAME'],
            description=f'Automated deployment triggered via lambda by ECR push: {image_uri}',
            revision={
                'revisionType': 'AppSpecContent',
                'appSpecContent': {
                    'content': json.dumps({
                        'version': 0.0,
                        'Resources': [{
                            'TargetService': {
                                'Type': 'AWS::Lambda::Function',
                                'Properties': {
                                    'Name': function_name,
                                    'Alias': 'live',
                                    'CurrentVersion': current_version,
                                    'TargetVersion': new_version
                                }
                            }
                        }],
                        'Hooks': []
                    })
                }
            }
        )
        
        print(f"Started deployment: {response['deploymentId']}")
        return {
            'statusCode': 200,
            'body': json.dumps({
                'deploymentId': response['deploymentId'],
                'message': f'Deployment started for {image_uri}'
            })
        }
        
    except Exception as e:
        print(f"Error creating deployment: {str(e)}")
        raise
