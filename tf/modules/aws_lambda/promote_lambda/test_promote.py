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

class TestPromoteLambda(unittest.TestCase):
    def setUp(self):
        """Set up test fixtures."""
        # Mock environment variables
        self.env_patcher = patch.dict(os.environ, {
            'APP_NAME': 'testapp',
            'ENV_NAME': 'prod',
            'DEV_ACCOUNT_ID': '123456789',
            'MANUAL_DEPLOY_FUNCTION_NAME': 'testapp-prod-manual-deploy',
            'AWS_REGION': 'us-east-1'
        })
        self.env_patcher.start()
        
        # Create mock clients
        self.mock_codedeploy = Mock()
        self.mock_ecr = Mock()
        self.mock_lambda = Mock()
        
        # Patch boto3 clients
        self.codedeploy_patcher = patch('index.codedeploy', self.mock_codedeploy)
        self.ecr_patcher = patch('index.ecr', self.mock_ecr)
        self.lambda_patcher = patch('index.lambda_client', self.mock_lambda)
        
        self.codedeploy_patcher.start()
        self.ecr_patcher.start()
        self.lambda_patcher.start()

    def tearDown(self):
        """Clean up after tests."""
        self.env_patcher.stop()
        self.codedeploy_patcher.stop()
        self.ecr_patcher.stop()
        self.lambda_patcher.stop()

    def test_get_ecr_image_sha_success(self):
        """Test successful ECR image SHA retrieval."""
        # Mock ECR response
        self.mock_ecr.describe_images.return_value = {
            'imageDetails': [{
                'imageDigest': 'sha256:abc123def456'
            }]
        }
        
        result = index.get_ecr_image_sha('test-repo', 'v1.0.0')
        
        self.assertEqual(result, 'sha256:abc123def456')
        self.mock_ecr.describe_images.assert_called_once_with(
            repositoryName='test-repo',
            imageIds=[{'imageTag': 'v1.0.0'}]
        )

    def test_get_ecr_image_sha_not_found(self):
        """Test ECR image SHA retrieval when image not found."""
        # Mock ECR response with no images
        self.mock_ecr.describe_images.return_value = {'imageDetails': []}
        
        result = index.get_ecr_image_sha('test-repo', 'nonexistent')
        
        self.assertIsNone(result)

    def test_get_ecr_image_sha_error(self):
        """Test ECR image SHA retrieval error handling."""
        # Mock ECR error
        self.mock_ecr.describe_images.side_effect = Exception("ECR Error")
        
        result = index.get_ecr_image_sha('test-repo', 'v1.0.0')
        
        self.assertIsNone(result)

    @patch('index.boto3')
    def test_get_latest_successful_dev_deployment_success(self, mock_boto3):
        """Test successful dev deployment retrieval."""
        # Mock STS assume role
        mock_sts = Mock()
        mock_boto3.client.side_effect = lambda service, **kwargs: {
            'sts': mock_sts,
            'codedeploy': Mock(),
            's3': Mock(),
            'lambda': Mock(),
            'ecr': Mock()
        }.get(service, Mock())
        
        mock_sts.assume_role.return_value = {
            'Credentials': {
                'AccessKeyId': 'AKIATEST',
                'SecretAccessKey': 'secret',
                'SessionToken': 'token'
            }
        }
        
        # Mock dev account clients
        mock_dev_codedeploy = Mock()
        mock_dev_s3 = Mock()
        mock_dev_lambda = Mock()
        mock_dev_ecr = Mock()
        
        # Set up the side_effect to return different mocks based on credentials
        def mock_client_side_effect(service, **kwargs):
            if 'aws_access_key_id' in kwargs:
                # This is a dev account client
                return {
                    'codedeploy': mock_dev_codedeploy,
                    's3': mock_dev_s3,
                    'lambda': mock_dev_lambda,
                    'ecr': mock_dev_ecr
                }.get(service, Mock())
            else:
                # This is a regular client
                return {
                    'sts': mock_sts
                }.get(service, Mock())
        
        mock_boto3.client.side_effect = mock_client_side_effect
        
        # Mock dev CodeDeploy responses
        mock_dev_codedeploy.list_deployments.return_value = {
            'deployments': ['deploy-123']
        }
        
        mock_dev_codedeploy.get_deployment.return_value = {
            'deploymentInfo': {
                'revision': {
                    'revisionType': 'S3',
                    's3Location': {
                        'bucket': 'testapp-dev-codedeploy-appspec',
                        'key': 'appspec-testapp-dev-5-20240101-120000.json'
                    }
                }
            }
        }
        
        # Mock S3 AppSpec content
        appspec_content = {
            'version': 0.0,
            'Resources': [{
                'TargetService': {
                    'Properties': {
                        'TargetVersion': '5'
                    }
                }
            }]
        }
        
        mock_s3_response = Mock()
        mock_s3_response.read.return_value = json.dumps(appspec_content).encode('utf-8')
        mock_dev_s3.get_object.return_value = {'Body': mock_s3_response}
        
        # Mock Lambda function info
        mock_dev_lambda.get_function.return_value = {
            'Code': {
                'ImageUri': '123456789.dkr.ecr.us-east-1.amazonaws.com/testapp-dev:v1.0.0@sha256:abc123'
            }
        }
        
        # Call the function
        result = index.get_latest_successful_dev_deployment('testapp', 'dev', '123456789')
        
        # Verify the result
        self.assertIsNotNone(result)
        self.assertEqual(result['deployment_id'], 'deploy-123')
        self.assertEqual(result['image_tag'], 'v1.0.0')
        self.assertEqual(result['image_sha'], 'sha256:abc123')
        self.assertEqual(result['target_version'], '5')

    @patch('index.boto3')
    def test_get_latest_successful_dev_deployment_no_deployments(self, mock_boto3):
        """Test dev deployment retrieval when no deployments found."""
        # Mock STS assume role
        mock_sts = Mock()
        mock_dev_codedeploy = Mock()
        
        mock_boto3.client.side_effect = lambda service, **kwargs: {
            'sts': mock_sts if 'aws_access_key_id' not in kwargs else Mock(),
            'codedeploy': mock_dev_codedeploy if 'aws_access_key_id' in kwargs else Mock()
        }.get(service, Mock())
        
        mock_sts.assume_role.return_value = {
            'Credentials': {
                'AccessKeyId': 'AKIATEST',
                'SecretAccessKey': 'secret',
                'SessionToken': 'token'
            }
        }
        
        # Mock empty deployments list
        mock_dev_codedeploy.list_deployments.return_value = {'deployments': []}
        
        result = index.get_latest_successful_dev_deployment('testapp', 'dev', '123456789')
        
        self.assertIsNone(result)

    @patch('index.boto3')
    def test_get_latest_successful_dev_deployment_assume_role_error(self, mock_boto3):
        """Test dev deployment retrieval when assume role fails."""
        mock_sts = Mock()
        mock_boto3.client.return_value = mock_sts
        
        # Mock assume role failure
        mock_sts.assume_role.side_effect = Exception("Access denied")
        
        with self.assertRaises(Exception):
            index.get_latest_successful_dev_deployment('testapp', 'dev', '123456789')

    def test_handler_success(self):
        """Test successful promotion flow."""
        # Mock context
        mock_context = Mock()
        mock_context.invoked_function_arn = 'arn:aws:lambda:us-east-1:987654321:function:testapp-prod-promote'
        
        # Test event
        test_event = {
            'release_tag': 'v1.0.0'
        }
        
        # Mock successful dev deployment
        mock_dev_deployment = {
            'deployment_id': 'deploy-123',
            'image_uri': '123456789.dkr.ecr.us-east-1.amazonaws.com/testapp-dev:v1.0.0@sha256:abc123',
            'image_tag': 'v1.0.0',
            'image_sha': 'sha256:abc123',
            'target_version': '5'
        }
        
        with patch('index.get_latest_successful_dev_deployment') as mock_get_dev, \
             patch('index.get_ecr_image_sha') as mock_get_sha:
            
            mock_get_dev.return_value = mock_dev_deployment
            mock_get_sha.return_value = 'sha256:abc123'  # Same SHA in prod
            
            # Mock successful manual deploy invoke
            self.mock_lambda.invoke.return_value = {'StatusCode': 202}
            
            result = index.handler(test_event, mock_context)
            
            # Verify success response
            self.assertEqual(result['statusCode'], 200)
            body = json.loads(result['body'])
            self.assertIn('Successfully promoted v1.0.0 from dev to prod', body['message'])
            self.assertEqual(body['dev_deployment'], mock_dev_deployment)
            self.assertEqual(body['image_sha'], 'sha256:abc123')
            
            # Verify function calls
            mock_get_dev.assert_called_once_with('testapp', 'prod', '123456789')
            mock_get_sha.assert_called_once_with('testapp-prod', 'v1.0.0')
            
            # Verify manual deploy was triggered
            self.mock_lambda.invoke.assert_called_once()
            invoke_args = self.mock_lambda.invoke.call_args
            self.assertEqual(invoke_args[1]['FunctionName'], 'testapp-prod-manual-deploy')
            self.assertEqual(invoke_args[1]['InvocationType'], 'Event')
            
            payload = json.loads(invoke_args[1]['Payload'])
            self.assertEqual(payload['image_tag'], 'v1.0.0')
            self.assertEqual(payload['release_tag'], 'v1.0.0')

    def test_handler_missing_release_tag(self):
        """Test handler with missing release tag."""
        test_event = {}
        mock_context = Mock()
        
        with self.assertRaises(ValueError) as cm:
            index.handler(test_event, mock_context)
        
        self.assertIn("Missing 'release_tag' in event", str(cm.exception))

    def test_handler_no_dev_deployment_found(self):
        """Test handler when no dev deployment is found."""
        test_event = {'release_tag': 'v1.0.0'}
        mock_context = Mock()
        mock_context.invoked_function_arn = 'arn:aws:lambda:us-east-1:987654321:function:testapp-prod-promote'
        
        with patch('index.get_latest_successful_dev_deployment') as mock_get_dev:
            mock_get_dev.return_value = None
            
            with self.assertRaises(ValueError) as cm:
                index.handler(test_event, mock_context)
            
            self.assertIn("No successful deployment found in dev account", str(cm.exception))

    def test_handler_image_not_in_prod_ecr(self):
        """Test handler when image not found in prod ECR."""
        test_event = {'release_tag': 'v1.0.0'}
        mock_context = Mock()
        mock_context.invoked_function_arn = 'arn:aws:lambda:us-east-1:987654321:function:testapp-prod-promote'
        
        mock_dev_deployment = {
            'deployment_id': 'deploy-123',
            'image_uri': '123456789.dkr.ecr.us-east-1.amazonaws.com/testapp-dev:v1.0.0@sha256:abc123',
            'image_tag': 'v1.0.0',
            'image_sha': 'sha256:abc123',
            'target_version': '5'
        }
        
        with patch('index.get_latest_successful_dev_deployment') as mock_get_dev, \
             patch('index.get_ecr_image_sha') as mock_get_sha:
            
            mock_get_dev.return_value = mock_dev_deployment
            mock_get_sha.return_value = None  # Image not found in prod
            
            with self.assertRaises(ValueError) as cm:
                index.handler(test_event, mock_context)
            
            self.assertIn("Image v1.0.0 not found in prod ECR repository", str(cm.exception))

    def test_handler_sha_mismatch(self):
        """Test handler when SHA mismatch between dev and prod."""
        test_event = {'release_tag': 'v1.0.0'}
        mock_context = Mock()
        mock_context.invoked_function_arn = 'arn:aws:lambda:us-east-1:987654321:function:testapp-prod-promote'
        
        mock_dev_deployment = {
            'deployment_id': 'deploy-123',
            'image_uri': '123456789.dkr.ecr.us-east-1.amazonaws.com/testapp-dev:v1.0.0@sha256:abc123',
            'image_tag': 'v1.0.0',
            'image_sha': 'sha256:abc123',
            'target_version': '5'
        }
        
        with patch('index.get_latest_successful_dev_deployment') as mock_get_dev, \
             patch('index.get_ecr_image_sha') as mock_get_sha:
            
            mock_get_dev.return_value = mock_dev_deployment
            mock_get_sha.return_value = 'sha256:different'  # Different SHA in prod
            
            with self.assertRaises(ValueError) as cm:
                index.handler(test_event, mock_context)
            
            self.assertIn("Image SHA mismatch!", str(cm.exception))
            self.assertIn("Dev: sha256:abc123", str(cm.exception))
            self.assertIn("Prod: sha256:different", str(cm.exception))

    def test_handler_manual_deploy_invoke_failure(self):
        """Test handler when manual deploy invocation fails."""
        test_event = {'release_tag': 'v1.0.0'}
        mock_context = Mock()
        mock_context.invoked_function_arn = 'arn:aws:lambda:us-east-1:987654321:function:testapp-prod-promote'
        
        mock_dev_deployment = {
            'deployment_id': 'deploy-123',
            'image_uri': '123456789.dkr.ecr.us-east-1.amazonaws.com/testapp-dev:v1.0.0@sha256:abc123',
            'image_tag': 'v1.0.0',
            'image_sha': 'sha256:abc123',
            'target_version': '5'
        }
        
        with patch('index.get_latest_successful_dev_deployment') as mock_get_dev, \
             patch('index.get_ecr_image_sha') as mock_get_sha:
            
            mock_get_dev.return_value = mock_dev_deployment
            mock_get_sha.return_value = 'sha256:abc123'
            
            # Mock lambda invoke failure
            self.mock_lambda.invoke.side_effect = Exception("Lambda invoke failed")
            
            with self.assertRaises(Exception) as cm:
                index.handler(test_event, mock_context)
            
            self.assertIn("Lambda invoke failed", str(cm.exception))

    def test_get_ecr_image_sha_with_client_success(self):
        """Test get_ecr_image_sha_with_client function."""
        mock_ecr_client = Mock()
        mock_ecr_client.describe_images.return_value = {
            'imageDetails': [{
                'imageDigest': 'sha256:test123'
            }]
        }
        
        result = index.get_ecr_image_sha_with_client(mock_ecr_client, 'test-repo', 'v1.0.0')
        
        self.assertEqual(result, 'sha256:test123')
        mock_ecr_client.describe_images.assert_called_once_with(
            repositoryName='test-repo',
            imageIds=[{'imageTag': 'v1.0.0'}]
        )

    def test_get_ecr_image_sha_with_client_no_images(self):
        """Test get_ecr_image_sha_with_client when no images found."""
        mock_ecr_client = Mock()
        mock_ecr_client.describe_images.return_value = {'imageDetails': []}
        
        result = index.get_ecr_image_sha_with_client(mock_ecr_client, 'test-repo', 'v1.0.0')
        
        self.assertIsNone(result)

    def test_get_ecr_image_sha_with_client_error(self):
        """Test get_ecr_image_sha_with_client error handling."""
        mock_ecr_client = Mock()
        mock_ecr_client.describe_images.side_effect = Exception("ECR Error")
        
        result = index.get_ecr_image_sha_with_client(mock_ecr_client, 'test-repo', 'v1.0.0')
        
        self.assertIsNone(result)


if __name__ == '__main__':
    # Run the tests
    unittest.main(verbosity=2)