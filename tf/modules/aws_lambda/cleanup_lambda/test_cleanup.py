import unittest
from unittest.mock import Mock, patch, MagicMock
import json
import os
from datetime import datetime, timezone
import sys

# Add the current directory to the path so we can import the module
sys.path.insert(0, os.path.dirname(__file__))

# Import the module under test
import index

class TestCleanupLambda(unittest.TestCase):
    def setUp(self):
        """Set up test fixtures."""
        # Mock environment variables
        self.env_patcher = patch.dict(os.environ, {
            'ECR_REPOSITORY_NAME': 'test-repo',
            'APPSPEC_BUCKET_NAME': 'test-bucket',
            'CODEDEPLOY_APP_NAME': 'test-app',
            'CODEDEPLOY_GROUP_NAME': 'test-group',
            'RETAIN_COUNT': '10',
            'SUCCESSFUL_DEPLOY_RETAIN': '3'
        })
        self.env_patcher.start()
        
        # Create mock clients
        self.mock_ecr = Mock()
        self.mock_s3 = Mock()
        self.mock_codedeploy = Mock()
        
        # Patch boto3 clients
        self.ecr_patcher = patch('index.ecr_client', self.mock_ecr)
        self.s3_patcher = patch('index.s3_client', self.mock_s3)
        self.codedeploy_patcher = patch('index.codedeploy_client', self.mock_codedeploy)
        
        self.ecr_patcher.start()
        self.s3_patcher.start()
        self.codedeploy_patcher.start()

    def tearDown(self):
        """Clean up after tests."""
        self.env_patcher.stop()
        self.ecr_patcher.stop()
        self.s3_patcher.stop()
        self.codedeploy_patcher.stop()

    def test_get_successful_deployment_artifacts_success(self):
        """Test successful extraction of deployment artifacts."""
        # Mock CodeDeploy responses
        self.mock_codedeploy.list_deployments.return_value = {
            'deployments': ['deploy-1', 'deploy-2', 'deploy-3']
        }
        
        # Mock deployment details
        deployment_details = [
            {
                'deploymentInfo': {
                    'description': 'Automated deployment triggered via lambda by ECR push: 123456789.dkr.ecr.us-east-1.amazonaws.com/test-repo:v1.0.0',
                    'revision': {
                        'revisionType': 'S3',
                        's3Location': {
                            'bucket': 'test-bucket',
                            'key': 'appspec-v1.0.0-20240101-120000.json'
                        }
                    }
                }
            },
            {
                'deploymentInfo': {
                    'description': 'Automated deployment triggered via lambda by ECR push: 123456789.dkr.ecr.us-east-1.amazonaws.com/test-repo:v2.0.0',
                    'revision': {
                        'revisionType': 'S3',
                        's3Location': {
                            'bucket': 'test-bucket', 
                            'key': 'appspec-v2.0.0-20240102-120000.json'
                        }
                    }
                }
            },
            {
                'deploymentInfo': {
                    'description': 'Automated deployment triggered via lambda by ECR push: 123456789.dkr.ecr.us-east-1.amazonaws.com/test-repo:v3.0.0',
                    'revision': {
                        'revisionType': 'S3',
                        's3Location': {
                            'bucket': 'test-bucket',
                            'key': 'appspec-v3.0.0-20240103-120000.json'
                        }
                    }
                }
            }
        ]
        
        self.mock_codedeploy.get_deployment.side_effect = deployment_details
        
        # Call the function
        result = index.get_successful_deployment_artifacts('test-app', 'test-group', 3)
        
        # Verify the result
        expected = {
            'image_tags': ['v1.0.0', 'v2.0.0', 'v3.0.0'],
            'appspec_keys': [
                'appspec-v1.0.0-20240101-120000.json',
                'appspec-v2.0.0-20240102-120000.json', 
                'appspec-v3.0.0-20240103-120000.json'
            ]
        }
        
        self.assertEqual(set(result['image_tags']), set(expected['image_tags']))
        self.assertEqual(set(result['appspec_keys']), set(expected['appspec_keys']))
        
        # Verify API calls
        self.mock_codedeploy.list_deployments.assert_called_once_with(
            applicationName='test-app',
            deploymentGroupName='test-group',
            includeOnlyStatuses=['Succeeded'],
            maxItems=3
        )
        self.assertEqual(self.mock_codedeploy.get_deployment.call_count, 3)

    def test_get_successful_deployment_artifacts_no_deployments(self):
        """Test when no successful deployments are found."""
        self.mock_codedeploy.list_deployments.return_value = {'deployments': []}
        
        result = index.get_successful_deployment_artifacts('test-app', 'test-group', 3)
        
        expected = {'image_tags': [], 'appspec_keys': []}
        self.assertEqual(result, expected)

    def test_get_successful_deployment_artifacts_error_handling(self):
        """Test error handling in get_successful_deployment_artifacts."""
        self.mock_codedeploy.list_deployments.side_effect = Exception("API Error")
        
        result = index.get_successful_deployment_artifacts('test-app', 'test-group', 3)
        
        # Should return empty lists on error
        expected = {'image_tags': [], 'appspec_keys': []}
        self.assertEqual(result, expected)

    def test_cleanup_ecr_images_with_protection(self):
        """Test ECR cleanup with protected images."""
        # Create test images (newest first)
        test_images = []
        for i in range(15):
            test_images.append({
                'imageTags': [f'v{i+1}.0.0'],
                'imageDigest': f'sha256:digest{i+1}',
                'imagePushedAt': datetime(2024, 1, i+1, tzinfo=timezone.utc)
            })
        
        # Mock ECR response
        self.mock_ecr.describe_images.return_value = {'imageDetails': test_images}
        
        # Protect the last 3 successful deployment images
        protected_tags = ['v1.0.0', 'v5.0.0', 'v8.0.0']  # Scattered throughout history
        
        # Call cleanup (retain 10, so normally would delete images 11-15)
        result = index.cleanup_ecr_images('test-repo', 10, protected_tags)
        
        # Verify batch_delete_image calls
        delete_calls = self.mock_ecr.batch_delete_image.call_args_list
        
        # Should delete images that are:
        # 1. Beyond the retain count (11-15, which are v4.0.0, v3.0.0, v2.0.0, v1.0.0)
        # 2. NOT in protected tags
        # So should delete v4.0.0, v3.0.0, v2.0.0 but NOT v1.0.0 (protected)
        
        deleted_tags = []
        for call in delete_calls:
            args, kwargs = call
            for image_id in kwargs['imageIds']:
                if 'imageTag' in image_id:
                    deleted_tags.append(image_id['imageTag'])
        
        # v1.0.0 should be protected, others should be deleted
        self.assertNotIn('v1.0.0', deleted_tags)  # Protected
        self.assertNotIn('v5.0.0', deleted_tags)  # Protected  
        self.assertNotIn('v8.0.0', deleted_tags)  # Protected
        
        # Should delete non-protected images beyond retain count
        self.assertIn('v4.0.0', deleted_tags)
        self.assertIn('v3.0.0', deleted_tags)
        self.assertIn('v2.0.0', deleted_tags)

    def test_cleanup_appspec_files_with_protection(self):
        """Test S3 AppSpec cleanup with protected files."""
        # Create test S3 objects (newest first by LastModified)
        test_objects = []
        for i in range(15):
            test_objects.append({
                'Key': f'appspec-v{i+1}.0.0-20240101-120000.json',
                'LastModified': datetime(2024, 1, i+1, tzinfo=timezone.utc)
            })
        
        # Mock S3 response
        self.mock_s3.list_objects_v2.return_value = {'Contents': test_objects}
        
        # Protect specific AppSpec files
        protected_keys = [
            'appspec-v1.0.0-20240101-120000.json',
            'appspec-v5.0.0-20240101-120000.json',
            'appspec-v8.0.0-20240101-120000.json'
        ]
        
        # Call cleanup (retain 10, so normally would delete files 11-15)
        result = index.cleanup_appspec_files('test-bucket', 10, protected_keys)
        
        # Verify delete_object calls
        delete_calls = self.mock_s3.delete_object.call_args_list
        deleted_keys = [call[1]['Key'] for call in delete_calls]
        
        # Protected files should not be deleted
        for protected_key in protected_keys:
            self.assertNotIn(protected_key, deleted_keys)
        
        # Non-protected files beyond retain count should be deleted
        self.assertIn('appspec-v4.0.0-20240101-120000.json', deleted_keys)
        self.assertIn('appspec-v3.0.0-20240101-120000.json', deleted_keys)
        self.assertIn('appspec-v2.0.0-20240101-120000.json', deleted_keys)

    def test_handler_integration(self):
        """Test the main handler function integration."""
        # Mock the context
        mock_context = Mock()
        mock_context.invoked_function_arn = 'arn:aws:lambda:us-east-1:123456789:function:test'
        
        # Mock event (CodeDeploy success event)
        test_event = {
            'source': 'aws.codedeploy',
            'detail-type': 'CodeDeploy Deployment State-change Notification',
            'detail': {
                'application-name': 'test-app',
                'deployment-group': 'test-group',
                'state': 'SUCCESS'
            }
        }
        
        # Mock successful deployment artifacts
        with patch('index.get_successful_deployment_artifacts') as mock_get_artifacts:
            mock_get_artifacts.return_value = {
                'image_tags': ['v1.0.0', 'v2.0.0'],
                'appspec_keys': ['appspec-v1.json', 'appspec-v2.json']
            }
            
            # Mock cleanup functions
            with patch('index.cleanup_ecr_images') as mock_ecr_cleanup, \
                 patch('index.cleanup_appspec_files') as mock_s3_cleanup:
                
                mock_ecr_cleanup.return_value = 3
                mock_s3_cleanup.return_value = 2
                
                # Call the handler
                result = index.handler(test_event, mock_context)
                
                # Verify the result
                self.assertEqual(result['statusCode'], 200)
                body = json.loads(result['body'])
                self.assertEqual(body['results']['ecr_images_deleted'], 3)
                self.assertEqual(body['results']['appspec_files_deleted'], 2)
                
                # Verify function calls
                mock_get_artifacts.assert_called_once_with('test-app', 'test-group', 3)
                mock_ecr_cleanup.assert_called_once_with('test-repo', 10, ['v1.0.0', 'v2.0.0'])
                mock_s3_cleanup.assert_called_once_with('test-bucket', 10, ['appspec-v1.json', 'appspec-v2.json'])

    def test_handler_error_handling(self):
        """Test handler error handling."""
        mock_context = Mock()
        test_event = {}
        
        # Mock an error in get_successful_deployment_artifacts
        with patch('index.get_successful_deployment_artifacts') as mock_get_artifacts:
            mock_get_artifacts.side_effect = Exception("Test error")
            
            result = index.handler(test_event, mock_context)
            
            self.assertEqual(result['statusCode'], 500)
            body = json.loads(result['body'])
            self.assertIn('Test error', body['results']['errors'][0])


if __name__ == '__main__':
    # Run the tests
    unittest.main(verbosity=2)