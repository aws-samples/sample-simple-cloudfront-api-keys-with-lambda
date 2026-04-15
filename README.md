# CloudFront Lambda@Edge API Key POC

This project implements a Lambda@Edge function for AWS CloudFront that provides a simple API Key proof-of-concept using custom authentication headers against a DynamoDB table before allowing requests to proceed. When used in conjunction with TLS encryption, this protects the headers from exfiltration by unauthorized third parties.

## Security Considerations
This code is PROOF OF CONCEPT. It is offered here as-is. This code demonstrates a way to utilize API Keys to authenticate end users. This code is NOT intended for use in production. It is strongly encouraged that users modify this code to meet their needs and validate the security of the code via their own mechanisms that meet their corporate security policies. 

## Overview

The Lambda@Edge function examines incoming requests for two custom headers:
- `X-POC-KeyID`: The unique identifier for the API key which should be unique to each customer. This is the less secure component of the key pair.
- `X-POC-KeyValue`: The secret value associated with the API key which should be unique to each customer. This is the secure component of the key pair and should be shared via secure channels. 

The function validates these headers against a DynamoDB table and returns:
- **200 OK**: If the KeyID is valid, active, and the KeyValue matches
- **401 Unauthorized**: If the KeyID is invalid, missing, disabled, or the KeyValue doesn't match

## Architecture

```
CloudFront Request
    ↓
Lambda@Edge (Viewer Request)
    ↓
Validate Headers (X-POC-KeyID, X-POC-KeyValue)
    ↓
Query DynamoDB Table
    ↓
Check: KeyID exists? State=Active? KeyValue matches?
    ↓
Allow Request or Return 401
```

## DynamoDB Table Schema

**Table Name**: `POC-KeyValidation`

| Column    | Type   | Description                                                      |
|-----------|--------|------------------------------------------------------------------|
| KeyID     | String | [Primary key] - Unique identifier for the key                    |
| KeyValue  | String | Secret value that must match the header                          |
| State     | String | Either "Active" or "Disabled"                                    |
| Customer  | String | Name of the customer associated with the KeyID or freeform notes |
|-----------|--------|------------------------------------------------------------------|

## Files
cloudfront-api-key-proof-of-concept/
├─ deployment/
│  ├─ `create_dynamodb_table.py`: Script to create the DynamoDB table and add sample data
│  ├─ `deploy.sh`: Automated deployment script for all AWS resources
│  ├─ `key.json.example`: Example template for testing the keys against the CloudFront endpoint. Used by `test_endpoint.sh`
│  ├─ `requirements.txt`: Python dependencies (boto3)
│  ├─ `test_endpoint.sh`: Script to test CloudFront distributions with keys from key.json
├─ img/
│  ├─ `Lambda_at_Edge_flowchart.png`: Flowchart diagram of the request processing
├─ html/
│  ├─ `config.php`: Configuration file for the PHP based key-management dashboard
│  ├─ `functions.php`: Contains functions that utilize the AWS PHP libraries for various AWS services
│  ├─ `index.php`: Default document for the key-management dashboard
│  ├─ `README.md`: Documentation for deploying the key-management dashboard
│  ├─ `style.css`: CSS style document for the dashboard.
├─ policies/
│  ├─ `dashboard_ec2_instance_policy.json`: A policy that allows an EC2 based web server to query the DynamoDB key database
│  ├─ `iam_policy.json`: The IAM policy needed to allow Lambda to read the DynamoDB database
│  ├─ `trust_policy`: Trust policy for Lambda
├─ `lambda_edge_auth.py`: The Lambda@Edge function code
├─ README.md (this document)


## Prerequisites

1. **AWS CLI**: Installed and configured with appropriate credentials
   ```bash
   aws configure
   ```

2. **Python 3.14**: Required for Lambda runtime
   ```bash
   python3 --version
   ```

3. **AWS Permissions**: Your AWS user/role needs permissions to:
   - Create/manage Lambda functions
   - Create/manage IAM roles and policies
   - Create/manage DynamoDB tables
   - Modify CloudFront distributions

4. **CloudFront Distribution**: You must have an existing CloudFront distribution

## Installation & Deployment

### Option 1: Automated Deployment (Recommended)

Run the deployment script which handles everything automatically:

```bash
chmod +x deploy.sh
./deploy.sh
```

The script will:
1. Create the DynamoDB table
2. Create IAM role and policies
3. Package and deploy the Lambda function
4. Publish a Lambda version
5. Display the Function ARN for CloudFront configuration

### Option 2: Manual Deployment

#### Step 1: Create DynamoDB Table

```bash
python3 create_dynamodb_table.py
```

When prompted, choose whether to add sample data for testing.

#### Step 2: Create IAM Role

```bash
# Create the role
aws iam create-role \
  --role-name Lambda-Edge-POC-Auth-Role \
  --assume-role-policy-document file://trust_policy.json \
  --region us-east-1

# Create and attach the policy
aws iam create-policy \
  --policy-name Lambda-Edge-POC-Auth-Policy \
  --policy-document file://iam_policy.json \
  --region us-east-1

# Attach policy to role (replace ACCOUNT_ID with your AWS account ID)
aws iam attach-role-policy \
  --role-name Lambda-Edge-POC-Auth-Role \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/Lambda-Edge-POC-Auth-Policy \
  --region us-east-1
```

#### Step 3: Deploy Lambda Function

```bash
# Package the function
zip lambda_package.zip lambda_edge_auth.py

# Create the function (replace ROLE_ARN with your role ARN)
aws lambda create-function \
  --function-name CloudFront-POC-Auth \
  --runtime python3.14 \
  --role ROLE_ARN \
  --handler lambda_edge_auth.lambda_handler \
  --zip-file fileb://lambda_package.zip \
  --timeout 5 \
  --memory-size 128 \
  --region us-east-1

# Publish a version
aws lambda publish-version \
  --function-name CloudFront-POC-Auth \
  --region us-east-1
```

#### Step 4: Configure CloudFront

1. Go to the AWS CloudFront console
2. Select your distribution
3. Go to the **Behaviors** tab
4. Edit the behavior you want to protect
5. Scroll to **Function associations**
6. Add a new association:
   - **Event type**: Viewer Request
   - **Function type**: Lambda@Edge
   - **Function ARN**: Use the versioned ARN from the deployment output
7. Save changes
8. Wait for the CloudFront distribution to deploy (this can take 15-30 minutes)

## Testing

### Automated Testing with test_endpoint.sh

The easiest way to test your CloudFront distribution is using the provided test script:

1. **Configure the CloudFront URL** in test_endpoint.sh:
   ```bash
   # Edit the CLOUDFRONT_URL variable at the top of the script
   CLOUDFRONT_URL="https://d1234567890abc.cloudfront.net"
   ```

2. **Create your test keys file** (copy from example):
   ```bash
   cp key.json.example key.json
   ```

3. **Edit key.json** with your test keys:
   ```json
   {
     "keys": [
       {
         "KeyID": "test-key-001",
         "KeyValue": "secret-value-001",
         "Description": "Valid active key"
       },
       {
         "KeyID": "invalid-key",
         "KeyValue": "wrong-value",
         "Description": "Should fail"
       }
     ]
   }
   ```

4. **Run the test script**:
   ```bash
   chmod +x test_endpoint.sh
   ./test_endpoint.sh
   ```

5. The script will:
   - Test each key from key.json against your configured CloudFront URL
   - Display results with pass/fail status
   - Provide a summary of all tests

### Add Test Data to DynamoDB

If you didn't add sample data during table creation, you can add items manually:

```bash
aws dynamodb put-item \
  --table-name POC-KeyValidation \
  --item '{
    "KeyID": {"S": "test-key-001"},
    "KeyValue": {"S": "secret-value-001"},
    "State": {"S": "Active"},
    "Customer": {"S": "Acme Corporation"}
  }' \
  --region us-east-1
```

### Manual Testing with cURL

**Valid Request (should succeed):**
```bash
curl -H "X-POC-KeyID: test-key-001" \
     -H "X-POC-KeyValue: secret-value-001" \
     https://your-cloudfront-domain.cloudfront.net/
```

**Invalid KeyValue (should return 401):**
```bash
curl -H "X-POC-KeyID: test-key-001" \
     -H "X-POC-KeyValue: wrong-value" \
     https://your-cloudfront-domain.cloudfront.net/
```

**Missing Headers (should return 401):**
```bash
curl https://your-cloudfront-domain.cloudfront.net/
```

**Disabled Key (should return 401):**
```bash
curl -H "X-POC-KeyID: test-key-003" \
     -H "X-POC-KeyValue: secret-value-003" \
     https://your-cloudfront-domain.cloudfront.net/
```

## Managing Keys

### Add a New Key

```bash
aws dynamodb put-item \
  --table-name POC-KeyValidation \
  --item '{
    "KeyID": {"S": "customer-key-123"},
    "KeyValue": {"S": "super-secret-value"},
    "State": {"S": "Active"},
    "Customer": {"S": "Customer Name"}
  }' \
  --region us-east-1
```

### Disable a Key

```bash
aws dynamodb update-item \
  --table-name POC-KeyValidation \
  --key '{"KeyID": {"S": "test-key-001"}}' \
  --update-expression "SET #state = :disabled" \
  --expression-attribute-names '{"#state": "State"}' \
  --expression-attribute-values '{":disabled": {"S": "Disabled"}}' \
  --region us-east-1
```

### Enable a Key

```bash
aws dynamodb update-item \
  --table-name POC-KeyValidation \
  --key '{"KeyID": {"S": "test-key-001"}}' \
  --update-expression "SET #state = :active" \
  --expression-attribute-names '{"#state": "State"}' \
  --expression-attribute-values '{":active": {"S": "Active"}}' \
  --region us-east-1
```

### Delete a Key

```bash
aws dynamodb delete-item \
  --table-name POC-KeyValidation \
  --key '{"KeyID": {"S": "test-key-001"}}' \
  --region us-east-1
```

## Monitoring

### View Lambda Logs

Lambda@Edge logs are created in CloudWatch Logs in the AWS region closest to where the function executed.

```bash
# List log groups (check multiple regions)
aws logs describe-log-groups \
  --log-group-name-prefix /aws/lambda/us-east-1.CloudFront-POC-Auth \
  --region us-east-1
```

### View Recent Log Events

```bash
aws logs tail /aws/lambda/us-east-1.CloudFront-POC-Auth \
  --follow \
  --region us-east-1
```

## Important Notes

1. **Region Requirement**: Lambda@Edge functions MUST be created in `us-east-1` region
2. **Versioning**: You must publish a new version of the Lambda function after any code changes
3. **Propagation Time**: CloudFront changes can take 15-30 minutes to propagate globally
4. **DynamoDB Costs**: The table uses on-demand billing mode (pay per request)
5. **Lambda@Edge Limits**: 
   - Maximum execution time: 5 seconds for viewer request
   - Maximum memory: 128 MB (configurable)
   - Maximum package size: 1 MB

## Security Considerations

1. **Secure Key Storage**: Consider using AWS Secrets Manager for KeyValue storage instead of DynamoDB
2. **Encryption**: Enable encryption at rest for the DynamoDB table
3. **HTTPS Only**: Ensure CloudFront is configured to require HTTPS
4. **Rate Limiting**: Consider implementing rate limiting to prevent brute force attacks
5. **Key Rotation**: Implement a key rotation policy for production use
6. **Audit Logging**: Enable CloudTrail for DynamoDB to track key access

## Troubleshooting

### Function Not Triggering

- Verify the function is associated with the correct CloudFront behavior
- Check that you're using a versioned ARN (not $LATEST)
- Wait for CloudFront distribution to finish deploying

### 401 Errors for Valid Keys

- Check CloudWatch Logs for error messages
- Verify the KeyID and KeyValue in DynamoDB
- Ensure the State is set to "Active"
- Check header names are exactly: `X-POC-KeyID` and `X-POC-KeyValue`

### DynamoDB Access Errors

- Verify IAM role has correct permissions
- Check the table name matches in both the Lambda code and DynamoDB
- Ensure the table is in us-east-1 region

## Cleanup

To remove all resources:

```bash
# Delete Lambda function
aws lambda delete-function \
  --function-name CloudFront-POC-Auth \
  --region us-east-1

# Delete IAM role and policy
aws iam detach-role-policy \
  --role-name Lambda-Edge-POC-Auth-Role \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/Lambda-Edge-POC-Auth-Policy

aws iam delete-role \
  --role-name Lambda-Edge-POC-Auth-Role

aws iam delete-policy \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/Lambda-Edge-POC-Auth-Policy

# Delete DynamoDB table
aws dynamodb delete-table \
  --table-name POC-KeyValidation \
  --region us-east-1
```

## License Summary

This sample code is made available under the MIT-0 license. See the LICENSE file.

## Support

For issues or questions, please refer to AWS documentation:
- [Lambda@Edge Documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-edge.html)
- [CloudFront Documentation](https://docs.aws.amazon.com/cloudfront/)
- [DynamoDB Documentation](https://docs.aws.amazon.com/dynamodb/)
