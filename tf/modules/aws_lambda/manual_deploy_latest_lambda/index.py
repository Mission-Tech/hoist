import json
import boto3
import os

# Initialize clients
ecr_client = boto3.client('ecr')
lambda_client = boto3.client('lambda')

def handler(event, context):
    """
    Manual deployment trigger that finds the latest ECR image and triggers deployment.
    
    Usage: Invoke this function with a test event (can be empty {})
    """
    print(f"Manual deploy triggered with event: {json.dumps(event)}")
    
    try:
        repository_name = os.environ['ECR_REPOSITORY_NAME']
        trigger_function_name = os.environ['TRIGGER_FUNCTION_NAME']
        
        print(f"Finding latest image in repository: {repository_name}")
        
        # Get the latest image from ECR
        response = ecr_client.describe_images(
            repositoryName=repository_name,
            filter={
                'tagStatus': 'TAGGED'
            }
        )
        
        if not response.get('imageDetails'):
            raise ValueError(f"No images found in repository {repository_name}")
        
        # Sort by image pushed date to get the latest
        latest_image = sorted(
            response['imageDetails'],
            key=lambda x: x['imagePushedAt'],
            reverse=True
        )[0]
        
        # Get the image tag (prefer non-latest tags)
        image_tag = None
        for tag in latest_image.get('imageTags', []):
            if tag != 'latest':
                image_tag = tag
                break
        
        if not image_tag and latest_image.get('imageTags'):
            image_tag = latest_image['imageTags'][0]
        
        if not image_tag:
            raise ValueError("No image tags found for latest image")
            
        print(f"Latest image tag: {image_tag}")
        print(f"Image digest: {latest_image['imageDigest']}")
        print(f"Pushed at: {latest_image['imagePushedAt']}")
        
        # Create a synthetic ECR push event to trigger deployment
        synthetic_event = {
            "version": "0",
            "id": "manual-deploy-trigger",
            "detail-type": "ECR Image Action",
            "source": "aws.ecr",
            "account": context.invoked_function_arn.split(':')[4],
            "time": latest_image['imagePushedAt'].isoformat(),
            "region": context.invoked_function_arn.split(':')[3],
            "detail": {
                "action-type": "PUSH",
                "result": "SUCCESS",
                "repository-name": repository_name,
                "image-tag": image_tag,
                "image-digest": latest_image['imageDigest']
            }
        }
        
        print(f"Triggering deployment with synthetic event")
        
        # Invoke the trigger function
        trigger_response = lambda_client.invoke(
            FunctionName=trigger_function_name,
            InvocationType='RequestResponse',
            Payload=json.dumps(synthetic_event)
        )
        
        trigger_result = json.loads(trigger_response['Payload'].read())
        print(f"Trigger function response: {json.dumps(trigger_result)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Manual deployment triggered successfully',
                'imageTag': image_tag,
                'imageDigest': latest_image['imageDigest'],
                'triggerResult': trigger_result
            })
        }
        
    except Exception as e:
        print(f"Error triggering manual deployment: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }