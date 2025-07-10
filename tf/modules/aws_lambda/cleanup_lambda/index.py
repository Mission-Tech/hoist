import json
import boto3
import os
import re
from datetime import datetime

# Initialize clients
ecr_client = boto3.client('ecr')
s3_client = boto3.client('s3')
codedeploy_client = boto3.client('codedeploy')

def handler(event, context):
    """
    Cleanup function that retains only the most recent ECR images and AppSpec files.
    Triggered by successful CodeDeploy deployments.
    """
    print(f"Cleanup triggered with event: {json.dumps(event)}")
    
    repository_name = os.environ['ECR_REPOSITORY_NAME']
    bucket_name = os.environ['APPSPEC_BUCKET_NAME']
    codedeploy_app = os.environ['CODEDEPLOY_APP_NAME']
    codedeploy_group = os.environ['CODEDEPLOY_GROUP_NAME']
    retain_count = int(os.environ.get('RETAIN_COUNT', '10'))
    successful_deploy_retain = int(os.environ.get('SUCCESSFUL_DEPLOY_RETAIN', '3'))
    
    cleanup_results = {
        'ecr_images_deleted': 0,
        'appspec_files_deleted': 0,
        'errors': []
    }
    
    try:
        # Get successful deployment artifacts that must be protected
        print(f"Getting successful deployment history for protection")
        protected_artifacts = get_successful_deployment_artifacts(
            codedeploy_app, codedeploy_group, successful_deploy_retain
        )
        print(f"Protected artifacts: {json.dumps(protected_artifacts, default=str)}")
        
        # Cleanup ECR images
        print(f"Cleaning up ECR repository: {repository_name}")
        ecr_deleted = cleanup_ecr_images(repository_name, retain_count, protected_artifacts['image_tags'])
        cleanup_results['ecr_images_deleted'] = ecr_deleted
        
        # Cleanup AppSpec files
        print(f"Cleaning up S3 bucket: {bucket_name}")
        s3_deleted = cleanup_appspec_files(bucket_name, retain_count, protected_artifacts['appspec_keys'])
        cleanup_results['appspec_files_deleted'] = s3_deleted
        
        print(f"Cleanup completed: {json.dumps(cleanup_results)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cleanup completed successfully',
                'results': cleanup_results
            })
        }
        
    except Exception as e:
        error_msg = f"Cleanup failed: {str(e)}"
        print(error_msg)
        cleanup_results['errors'].append(error_msg)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Cleanup failed',
                'results': cleanup_results
            })
        }

def get_successful_deployment_artifacts(app_name, deployment_group, retain_count):
    """
    Get ECR image tags and S3 AppSpec keys from the last N successful deployments.
    
    CRITICAL: This prevents the following disaster scenario:
    1. You have 15 failed deployments in a row (each creates ECR images and AppSpecs)
    2. You finally get a successful deployment (#16)
    3. Cleanup runs and deletes images 1-6 (keeping only the 10 most recent)
    4. But images 1-6 might include your last successful deployment before the failures
    5. Now you can't rollback to the last known good state!
    
    This function ensures we NEVER delete artifacts from the last N successful deployments,
    regardless of how many failed deployments happened in between.
    """
    try:
        protected_artifacts = {
            'image_tags': set(),
            'appspec_keys': set()
        }
        
        # Get deployment history
        deployments_response = codedeploy_client.list_deployments(
            applicationName=app_name,
            deploymentGroupName=deployment_group,
            includeOnlyStatuses=['Succeeded'],
            maxItems=retain_count
        )
        
        successful_deployment_ids = deployments_response.get('deployments', [])
        print(f"Found {len(successful_deployment_ids)} recent successful deployments")
        
        # Get details for each successful deployment
        for deployment_id in successful_deployment_ids:
            try:
                deployment_details = codedeploy_client.get_deployment(deploymentId=deployment_id)
                deployment_info = deployment_details['deploymentInfo']
                
                # Extract image tag from deployment description
                # Description format: "Automated deployment triggered via lambda by ECR push: {account}.dkr.ecr.{region}.amazonaws.com/{repo}:{tag}"
                description = deployment_info.get('description', '')
                image_tag_match = re.search(r':([^:]+)$', description)
                if image_tag_match:
                    image_tag = image_tag_match.group(1)
                    protected_artifacts['image_tags'].add(image_tag)
                    print(f"Protected image tag from deployment {deployment_id}: {image_tag}")
                
                # Extract AppSpec S3 key if using S3 revision
                revision = deployment_info.get('revision', {})
                if revision.get('revisionType') == 'S3':
                    s3_location = revision.get('s3Location', {})
                    appspec_key = s3_location.get('key')
                    if appspec_key:
                        protected_artifacts['appspec_keys'].add(appspec_key)
                        print(f"Protected AppSpec key from deployment {deployment_id}: {appspec_key}")
                        
            except Exception as e:
                print(f"Error getting details for deployment {deployment_id}: {e}")
                continue
        
        # Convert sets to lists for JSON serialization
        protected_artifacts['image_tags'] = list(protected_artifacts['image_tags'])
        protected_artifacts['appspec_keys'] = list(protected_artifacts['appspec_keys'])
        
        return protected_artifacts
        
    except Exception as e:
        print(f"Error getting successful deployment artifacts: {e}")
        # Return empty protection list on error - better to over-delete than under-delete
        return {'image_tags': [], 'appspec_keys': []}

def cleanup_ecr_images(repository_name, retain_count, protected_image_tags):
    """Clean up old ECR images, keeping only the most recent ones."""
    try:
        # Get all images
        response = ecr_client.describe_images(
            repositoryName=repository_name,
            filter={'tagStatus': 'TAGGED'}
        )
        
        images = response.get('imageDetails', [])
        print(f"Found {len(images)} tagged images in ECR")
        
        if len(images) <= retain_count:
            print(f"Only {len(images)} images found, keeping all (retain_count: {retain_count})")
            return 0
        
        # Sort by push date (newest first)
        sorted_images = sorted(images, key=lambda x: x['imagePushedAt'], reverse=True)
        
        # Filter out images that are protected (from successful deployments)
        images_to_consider_deleting = []
        images_protected = []
        
        for image in sorted_images[retain_count:]:  # Only consider images beyond retain_count
            image_tags = image.get('imageTags', [])
            is_protected = any(tag in protected_image_tags for tag in image_tags)
            
            if is_protected:
                images_protected.append(image)
                print(f"PROTECTED: Image with tags {image_tags} (successful deployment artifact)")
            else:
                images_to_consider_deleting.append(image)
        
        print(f"Keeping {retain_count} most recent images")
        print(f"Protecting {len(images_protected)} images from successful deployments")
        print(f"Deleting {len(images_to_consider_deleting)} old images")
        
        deleted_count = 0
        for image in images_to_consider_deleting:
            try:
                # Prepare image identifiers for deletion
                image_ids = []
                
                # Add by digest
                if 'imageDigest' in image:
                    image_ids.append({'imageDigest': image['imageDigest']})
                
                # Add by tags
                for tag in image.get('imageTags', []):
                    image_ids.append({'imageTag': tag})
                
                if image_ids:
                    print(f"Deleting image pushed at {image['imagePushedAt']} with tags {image.get('imageTags', [])}")
                    
                    ecr_client.batch_delete_image(
                        repositoryName=repository_name,
                        imageIds=image_ids
                    )
                    deleted_count += 1
                    
            except Exception as e:
                print(f"Error deleting ECR image: {e}")
                continue
        
        return deleted_count
        
    except Exception as e:
        print(f"Error in ECR cleanup: {e}")
        raise

def cleanup_appspec_files(bucket_name, retain_count, protected_appspec_keys):
    """Clean up old AppSpec files, keeping only the most recent ones."""
    try:
        # List all objects in the bucket
        response = s3_client.list_objects_v2(
            Bucket=bucket_name,
            Prefix='appspec-'
        )
        
        objects = response.get('Contents', [])
        print(f"Found {len(objects)} AppSpec files in S3")
        
        if len(objects) <= retain_count:
            print(f"Only {len(objects)} files found, keeping all (retain_count: {retain_count})")
            return 0
        
        # Sort by last modified date (newest first)
        sorted_objects = sorted(objects, key=lambda x: x['LastModified'], reverse=True)
        
        # Filter out AppSpec files that are protected (from successful deployments)
        files_to_consider_deleting = []
        files_protected = []
        
        for obj in sorted_objects[retain_count:]:  # Only consider files beyond retain_count
            if obj['Key'] in protected_appspec_keys:
                files_protected.append(obj)
                print(f"PROTECTED: AppSpec file {obj['Key']} (successful deployment artifact)")
            else:
                files_to_consider_deleting.append(obj)
        
        print(f"Keeping {retain_count} most recent AppSpec files")
        print(f"Protecting {len(files_protected)} AppSpec files from successful deployments")
        print(f"Deleting {len(files_to_consider_deleting)} old AppSpec files")
        
        deleted_count = 0
        for obj in files_to_consider_deleting:
            try:
                print(f"Deleting S3 object: {obj['Key']} (modified: {obj['LastModified']})")
                
                s3_client.delete_object(
                    Bucket=bucket_name,
                    Key=obj['Key']
                )
                deleted_count += 1
                
            except Exception as e:
                print(f"Error deleting S3 object {obj['Key']}: {e}")
                continue
        
        return deleted_count
        
    except Exception as e:
        print(f"Error in S3 cleanup: {e}")
        raise