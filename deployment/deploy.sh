#!/bin/bash

# Deployment script for Lambda@Edge CloudFront Authentication
# This script creates all necessary AWS resources and deploys the Lambda function

set -e  # Exit on error

# Configuration
FUNCTION_NAME="CloudFront-POC-Auth"
ROLE_NAME="Lambda-Edge-POC-Auth-Role"
POLICY_NAME="Lambda-Edge-POC-Auth-Policy"
TABLE_NAME="POC-KeyValidation"
REGION="us-east-1"  # Lambda@Edge must be deployed in us-east-1
PYTHON_RUNTIME="python3.14"

echo "=========================================="
echo "Lambda@Edge Deployment Script"
echo "=========================================="
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo "Error: AWS credentials not configured. Please run 'aws configure'."
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "✓ AWS Account ID: $ACCOUNT_ID"
echo ""

# Step 1: Create DynamoDB Table
echo "Step 1: Creating DynamoDB table..."
echo "----------------------------------------"
python3 create_dynamodb_table.py
echo ""

# Step 2: Create IAM Role
echo "Step 2: Creating IAM role..."
echo "----------------------------------------"
if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
    echo "Role $ROLE_NAME already exists."
    ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
else
    ROLE_ARN=$(aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file://../policies/trust_policy.json \
        --query 'Role.Arn' \
        --output text \
        --region "$REGION")
    echo "✓ Created role: $ROLE_ARN"
fi
echo ""

# Step 3: Attach IAM Policy
echo "Step 3: Attaching IAM policy..."
echo "----------------------------------------"
# Update the policy with the actual account ID
sed "s/\*/$ACCOUNT_ID/g" ../policies/iam_policy.json > iam_policy_updated.json

if aws iam get-policy --policy-arn "arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME" &> /dev/null; then
    echo "Policy $POLICY_NAME already exists. Updating..."
    # Get the current policy version
    POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"
    
    # Create a new version
    aws iam create-policy-version \
        --policy-arn "$POLICY_ARN" \
        --policy-document file://iam_policy_updated.json \
        --set-as-default \
        --region "$REGION" > /dev/null
    echo "✓ Updated policy: $POLICY_ARN"
else
    POLICY_ARN=$(aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file://iam_policy_updated.json \
        --query 'Policy.Arn' \
        --output text \
        --region "$REGION")
    echo "✓ Created policy: $POLICY_ARN"
fi

# Attach policy to role
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "$POLICY_ARN" \
    --region "$REGION" 2>/dev/null || echo "Policy already attached to role."

echo "✓ Policy attached to role"
echo ""

# Step 4: Wait for IAM role propagation
echo "Step 4: Waiting for IAM role propagation..."
echo "----------------------------------------"
echo "Waiting 10 seconds for IAM changes to propagate..."
sleep 10
echo "✓ IAM propagation complete"
echo ""

# Step 5: Package Lambda function
echo "Step 5: Packaging Lambda function..."
echo "----------------------------------------"
# Create a temporary directory for packaging
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Copy Lambda function
cp lambda_edge_auth.py "$TEMP_DIR/"

# Create deployment package
cd "$TEMP_DIR"
zip -q lambda_package.zip lambda_edge_auth.py
cd - > /dev/null

echo "✓ Lambda package created"
echo ""

# Step 6: Create or Update Lambda function
echo "Step 6: Deploying Lambda function..."
echo "----------------------------------------"
if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$REGION" &> /dev/null; then
    echo "Function exists. Updating code..."
    aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --zip-file "fileb://$TEMP_DIR/lambda_package.zip" \
        --region "$REGION" > /dev/null
    echo "✓ Function code updated"
    
    # Wait for update to complete
    echo "Waiting for function update to complete..."
    aws lambda wait function-updated \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION"
    echo "✓ Function update complete"
else
    echo "Creating new function..."
    aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime "$PYTHON_RUNTIME" \
        --role "$ROLE_ARN" \
        --handler lambda_edge_auth.lambda_handler \
        --zip-file "fileb://$TEMP_DIR/lambda_package.zip" \
        --timeout 5 \
        --memory-size 128 \
        --region "$REGION" > /dev/null
    echo "✓ Function created"
    
    # Wait for function to be active
    echo "Waiting for function to become active..."
    aws lambda wait function-active \
        --function-name "$FUNCTION_NAME" \
        --region "$REGION"
    echo "✓ Function is now active"
fi
echo ""

# Step 7: Publish Lambda version
echo "Step 7: Publishing Lambda version..."
echo "----------------------------------------"
VERSION=$(aws lambda publish-version \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --query 'Version' \
    --output text)
echo "✓ Published version: $VERSION"

FUNCTION_ARN=$(aws lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --region "$REGION" \
    --query 'Configuration.FunctionArn' \
    --output text)
VERSIONED_ARN="$FUNCTION_ARN:$VERSION"
echo "✓ Function ARN: $VERSIONED_ARN"
echo ""

# Cleanup
rm -rf "$TEMP_DIR"
rm -f iam_policy_updated.json

# Step 8: Attach to CloudFront Distribution
echo "Step 8: Attaching to CloudFront distribution..."
echo "----------------------------------------"

# Get list of CloudFront distributions
echo "Fetching CloudFront distributions..."
DISTRIBUTIONS=$(aws cloudfront list-distributions --query 'DistributionList.Items[*].[Id,DomainName,Comment,Status]' --output text 2>/dev/null)

if [ -z "$DISTRIBUTIONS" ]; then
    echo "No CloudFront distributions found in your account."
    echo "You'll need to manually attach the Lambda function to your distribution."
    echo ""
    SKIP_CLOUDFRONT=true
else
    echo ""
    echo "Available CloudFront Distributions:"
    echo "-----------------------------------"
    
    # Parse and display distributions
    DIST_ARRAY=()
    INDEX=1
    while IFS=$'\t' read -r dist_id domain comment status; do
        DIST_ARRAY+=("$dist_id")
        if [ -z "$comment" ]; then
            comment="(no description)"
        fi
        echo "$INDEX) ID: $dist_id"
        echo "   Domain: $domain"
        echo "   Description: $comment"
        echo "   Status: $status"
        echo ""
        INDEX=$((INDEX + 1))
    done <<< "$DISTRIBUTIONS"
    
    # Prompt user to select a distribution
    echo "Enter the number of the distribution to attach the Lambda function to"
    echo "(or press Enter to skip CloudFront configuration):"
    read -r SELECTION
    
    if [ -z "$SELECTION" ]; then
        echo "Skipping CloudFront configuration."
        SKIP_CLOUDFRONT=true
    elif [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -lt "$INDEX" ]; then
        SELECTED_DIST_ID="${DIST_ARRAY[$((SELECTION - 1))]}"
        echo ""
        echo "Selected distribution: $SELECTED_DIST_ID"
        echo ""
        
        # Get current distribution config
        echo "Fetching distribution configuration..."
        aws cloudfront get-distribution-config \
            --id "$SELECTED_DIST_ID" \
            --output json > /tmp/dist-config.json
        
        ETAG=$(jq -r '.ETag' /tmp/dist-config.json)
        
        # Update the default cache behavior to include Lambda@Edge function
        echo "Updating distribution configuration..."
        jq --arg arn "$VERSIONED_ARN" \
            '.DistributionConfig.DefaultCacheBehavior.LambdaFunctionAssociations.Quantity = 1 |
             .DistributionConfig.DefaultCacheBehavior.LambdaFunctionAssociations.Items = [{
                "LambdaFunctionARN": $arn,
                "EventType": "viewer-request",
                "IncludeBody": false
             }]' /tmp/dist-config.json | jq '.DistributionConfig' > /tmp/dist-config-updated.json
        
        # Update the distribution
        echo "Applying changes to CloudFront distribution..."
        aws cloudfront update-distribution \
            --id "$SELECTED_DIST_ID" \
            --distribution-config file:///tmp/dist-config-updated.json \
            --if-match "$ETAG" > /dev/null
        
        echo "✓ Lambda function attached to CloudFront distribution"
        echo "✓ Distribution ID: $SELECTED_DIST_ID"
        echo ""
        echo "Note: CloudFront changes can take 15-30 minutes to propagate globally."
        echo ""
        
        # Cleanup temp files
        rm -f /tmp/dist-config.json /tmp/dist-config-updated.json
        
        SKIP_CLOUDFRONT=false
    else
        echo "Invalid selection. Skipping CloudFront configuration."
        SKIP_CLOUDFRONT=true
    fi
fi

echo ""

# Step 9: Display completion summary
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""

if [ "$SKIP_CLOUDFRONT" = true ]; then
    echo "Manual CloudFront Configuration Required:"
    echo "1. Go to CloudFront console"
    echo "2. Select your distribution"
    echo "3. Go to Behaviors tab"
    echo "4. Edit the behavior you want to protect"
    echo "5. Under 'Function associations', add:"
    echo "   - Event type: Viewer Request"
    echo "   - Function ARN: $VERSIONED_ARN"
    echo "6. Save changes and wait for deployment"
    echo ""
fi

echo "Testing:"
echo "Use the following headers in your requests:"
echo "  X-POC-KeyID: test-key-001"
echo "  X-POC-KeyValue: secret-value-001"
echo ""
echo "Resources Created:"
echo "  DynamoDB Table: $TABLE_NAME (in $REGION)"
echo "  Lambda Function: $FUNCTION_NAME (in $REGION)"
echo "  Lambda Version ARN: $VERSIONED_ARN"
echo "  IAM Role: $ROLE_NAME"
echo ""
echo "=========================================="
