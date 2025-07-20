import json
import boto3
import os
from urllib.parse import unquote_plus

codepipeline = boto3.client('codepipeline')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to trigger CodePipeline when terraform artifacts are uploaded to S3
    """
    
    branch_pipeline_name = os.environ['BRANCH_PIPELINE_NAME']
    main_pipeline_name = os.environ['MAIN_PIPELINE_NAME']
    
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        print(f"Processing S3 event for: s3://{bucket}/{key}")
        
        # Parse the S3 key to determine deployment type
        # Expected format: branch/terraform-TIMESTAMP-SHA.zip or main/terraform-TIMESTAMP-SHA.zip
        path_parts = key.split('/')
        if len(path_parts) < 2:
            print(f"Skipping {key} - unexpected format")
            continue
            
        deployment_type = path_parts[0]
        artifact_name = path_parts[1]
        
        # Only process terraform artifacts
        if not artifact_name.startswith('terraform-') or not artifact_name.endswith('.zip'):
            print(f"Skipping {key} - not a terraform artifact")
            continue
        
        # Get S3 object metadata
        try:
            obj_metadata = s3.head_object(Bucket=bucket, Key=key)
            s3_metadata = obj_metadata.get('Metadata', {})
            
            # Extract relevant metadata
            commit_sha = s3_metadata.get('commit-sha', 'unknown')
            branch = s3_metadata.get('branch', 'unknown')
            author = s3_metadata.get('author', 'unknown')
            
        except Exception as e:
            print(f"Error getting S3 metadata: {e}")
            s3_metadata = {}
            commit_sha = branch = author = 'unknown'
        
        # Determine which pipeline to trigger based on deployment type
        if deployment_type == 'branch':
            pipeline_name = branch_pipeline_name
            action = 'plan'
        elif deployment_type == 'main':
            pipeline_name = main_pipeline_name
            action = 'apply'
        else:
            print(f"Skipping {key} - unexpected deployment type: {deployment_type}")
            continue
        
        # Prepare pipeline execution parameters
        parameters = {
            'sourceS3Bucket': bucket,
            'sourceS3Key': key,
            'commitSha': commit_sha,
            'branch': branch,
            'author': author
        }
        
        # Start pipeline execution
        try:
            response = codepipeline.start_pipeline_execution(
                name=pipeline_name,
                variables=[
                    {'name': k, 'value': v} for k, v in parameters.items()
                ],
                pipelineExecutionDescription=f"Triggered by S3 upload: {key}"
            )
            
            execution_id = response['pipelineExecutionId']
            print(f"Started pipeline execution: {execution_id}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Pipeline triggered successfully',
                    'executionId': execution_id,
                    'artifact': key,
                    'action': parameters['action']
                })
            }
            
        except Exception as e:
            print(f"Error starting pipeline: {e}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'No valid artifacts to process'})
    }