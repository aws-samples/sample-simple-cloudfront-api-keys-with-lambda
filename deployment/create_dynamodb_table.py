"""
Script to create the DynamoDB table for POC key validation.
This table stores KeyID, KeyValue, State, and Customer information.
"""

import boto3
from botocore.exceptions import ClientError

# Table configuration
TABLE_NAME = 'POC-KeyValidation'
REGION = 'us-east-1'  # Lambda@Edge requires resources in us-east-1


def create_table():
    """
    Create the DynamoDB table for key validation.
    """
    dynamodb = boto3.client('dynamodb', region_name=REGION)
    
    try:
        response = dynamodb.create_table(
            TableName=TABLE_NAME,
            KeySchema=[
                {
                    'AttributeName': 'KeyID',
                    'KeyType': 'HASH'  # Partition key
                }
            ],
            AttributeDefinitions=[
                {
                    'AttributeName': 'KeyID',
                    'AttributeType': 'S'  # String
                }
            ],
            BillingMode='PAY_PER_REQUEST',  # On-demand billing
            Tags=[
                {
                    'Key': 'Purpose',
                    'Value': 'CloudFront-Authentication'
                },
                {
                    'Key': 'Project',
                    'Value': 'POC-KeyValidation'
                }
            ]
        )
        
        print(f"Creating table {TABLE_NAME}...")
        print(f"Table ARN: {response['TableDescription']['TableArn']}")
        
        # Wait for table to be created
        waiter = dynamodb.get_waiter('table_exists')
        waiter.wait(TableName=TABLE_NAME)
        
        print(f"✓ Table {TABLE_NAME} created successfully!")
        return True
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceInUseException':
            print(f"Table {TABLE_NAME} already exists.")
            return True
        else:
            print(f"Error creating table: {e}")
            return False


def add_sample_data():
    """
    Add sample data to the table for testing.
    """
    dynamodb = boto3.resource('dynamodb', region_name=REGION)
    table = dynamodb.Table(TABLE_NAME)
    
    sample_items = [
        {
            'KeyID': 'test-key-001',
            'KeyValue': 'secret-value-001',
            'State': 'Active',
            'Customer': 'Acme Corporation'
        },
        {
            'KeyID': 'test-key-002',
            'KeyValue': 'secret-value-002',
            'State': 'Active',
            'Customer': 'Beta Industries'
        },
        {
            'KeyID': 'test-key-003',
            'KeyValue': 'secret-value-003',
            'State': 'Disabled',
            'Customer': 'Gamma LLC'
        }
    ]
    
    print("\nAdding sample data...")
    for item in sample_items:
        try:
            table.put_item(Item=item)
            print(f"✓ Added KeyID: {item['KeyID']} for {item['Customer']} (State: {item['State']})")
        except ClientError as e:
            print(f"Error adding item {item['KeyID']}: {e}")
    
    print("\nSample data added successfully!")


if __name__ == '__main__':
    print("=" * 60)
    print("DynamoDB Table Creation for POC Key Validation")
    print("=" * 60)
    
    if create_table():
        # Optionally add sample data
        response = input("\nWould you like to add sample data? (yes/no): ")
        if response.lower() in ['yes', 'y']:
            add_sample_data()
    
    print("\n" + "=" * 60)
    print("Setup complete!")
    print("=" * 60)
