"""
Lambda@Edge function for CloudFront request authentication.
This function validates custom headers X-POC-KeyID and X-POC-KeyValue
against a DynamoDB table before allowing requests to proceed.
"""

import json
import boto3
from botocore.exceptions import ClientError

# Initialize DynamoDB client with explicit region
# Lambda@Edge functions need to specify the region for DynamoDB access
dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
# Table name
TABLE_NAME = 'POC-KeyValidation'


def lambda_handler(event, context):
    """
    Lambda@Edge handler for viewer request events.
    
    Args:
        event: CloudFront viewer request event
        context: Lambda context object
        
    Returns:
        CloudFront response object (either the original request or 401 error)
    """
    
    # Extract the request from the CloudFront event
    request = event['Records'][0]['cf']['request']
    headers = request['headers']
    
    # Extract custom headers (case-insensitive lookup)
    key_id = None
    key_value = None
    
    # CloudFront converts header names to lowercase
    if 'x-poc-keyid' in headers:
        key_id = headers['x-poc-keyid'][0]['value']
    
    if 'x-poc-keyvalue' in headers:
        key_value = headers['x-poc-keyvalue'][0]['value']
    
    # Check if both headers are present
    if not key_id or not key_value:
        return generate_401_response('Missing required authentication headers')
    
    # Validate against DynamoDB
    try:
        table = dynamodb.Table(TABLE_NAME)
        
        # Query DynamoDB for the KeyID
        response = table.get_item(
            Key={
                'KeyID': key_id
            }
        )
        
        # Check if item exists
        if 'Item' not in response:
            return generate_401_response('Invalid KeyID')
        
        item = response['Item']
        
        # Validate State is Active
        if item.get('State') != 'Active':
            return generate_401_response('KeyID is not active')
        
        # Validate KeyValue matches
        if item.get('KeyValue') != key_value:
            return generate_401_response('Invalid KeyValue')
        
        # All validations passed, allow the request to proceed
        print(f"Authentication successful for KeyID: {key_id}, Customer: {item.get('Customer', 'Unknown')}")
        return request
        
    except ClientError as e:
        print(f"DynamoDB error: {str(e)}")
        return generate_401_response('Authentication service error')
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return generate_401_response('Authentication failed')


def generate_401_response(message):
    """
    Generate a 401 Unauthorized response.
    
    Args:
        message: Error message to include in response
        
    Returns:
        CloudFront response object with 401 status
    """
    response = {
        'status': '401',
        'statusDescription': 'Unauthorized',
        'headers': {
            'content-type': [{
                'key': 'Content-Type',
                'value': 'application/json'
            }],
            'cache-control': [{
                'key': 'Cache-Control',
                'value': 'no-store, no-cache, must-revalidate'
            }]
        },
        'body': json.dumps({
            'error': 'Unauthorized',
            'message': message
        })
    }
    
    return response
