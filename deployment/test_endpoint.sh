#!/bin/bash

# Test script for CloudFront Lambda@Edge Authentication
# This script tests CloudFront distributions with keys from key.json

set -e  # Exit on error

# ============================================
# CONFIGURATION - Update this variable
# ============================================
CLOUDFRONT_URL="YOUR_CLOUDFRONT_ENDPOINT_URL"

echo "=========================================="
echo "CloudFront Authentication Test Script"
echo "=========================================="
echo ""

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "Error: curl is not installed. Please install it first."
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install it first."
    echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

# Check if key.json exists
if [ ! -f "key.json" ]; then
    echo "Error: key.json file not found in current directory."
    echo ""
    echo "Please create a key.json file with the following format:"
    echo '{'
    echo '  "keys": ['
    echo '    {'
    echo '      "KeyID": "test-key-001",'
    echo '      "KeyValue": "secret-value-001",'
    echo '      "Description": "Valid active key"'
    echo '    },'
    echo '    {'
    echo '      "KeyID": "test-key-002",'
    echo '      "KeyValue": "secret-value-002",'
    echo '      "Description": "Another valid key"'
    echo '    }'
    echo '  ]'
    echo '}'
    exit 1
fi

# Validate key.json format
if ! jq empty key.json 2>/dev/null; then
    echo "Error: key.json is not valid JSON."
    exit 1
fi

# Check if CloudFront URL is configured
if [ "$CLOUDFRONT_URL" = "https://your-distribution.cloudfront.net" ]; then
    echo "⚠ WARNING: CLOUDFRONT_URL is not configured!"
    echo ""
    echo "Please edit test_endpoint.sh and update the CLOUDFRONT_URL variable"
    echo "at the top of the script with your actual CloudFront distribution URL."
    echo ""
    echo "Example: CLOUDFRONT_URL=\"https://d1234567890abc.cloudfront.net\""
    echo ""
    exit 1
fi

echo "Testing CloudFront URL: $CLOUDFRONT_URL"
echo ""

# Read keys from key.json
echo "=========================================="
echo "Loading test keys from key.json..."
echo "=========================================="
echo ""

KEY_COUNT=$(jq '.keys | length' key.json)
echo "Found $KEY_COUNT key(s) to test"
echo ""

# Test each key
TEST_URL="$CLOUDFRONT_URL"
PASSED=0
FAILED=0

for i in $(seq 0 $((KEY_COUNT - 1))); do
    KEY_ID=$(jq -r ".keys[$i].KeyID" key.json)
    KEY_VALUE=$(jq -r ".keys[$i].KeyValue" key.json)
    DESCRIPTION=$(jq -r ".keys[$i].Description // \"No description\"" key.json)
    
    echo "=========================================="
    echo "Test $((i + 1)) of $KEY_COUNT"
    echo "=========================================="
    echo "KeyID: $KEY_ID"
    echo "Description: $DESCRIPTION"
    echo ""
    
    # Make the request
    echo "Testing with curl..."
    HTTP_CODE=$(curl -s -o /tmp/response_body.txt -w "%{http_code}" \
        -H "X-POC-KeyID: $KEY_ID" \
        -H "X-POC-KeyValue: $KEY_VALUE" \
        "$TEST_URL")
    
    RESPONSE_BODY=$(cat /tmp/response_body.txt)
    
    echo "HTTP Status Code: $HTTP_CODE"
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ PASSED - Authentication successful"
        PASSED=$((PASSED + 1))
    elif [ "$HTTP_CODE" = "401" ]; then
        echo "✗ FAILED - Authentication rejected (401 Unauthorized)"
        echo "Response: $RESPONSE_BODY"
        FAILED=$((FAILED + 1))
    else
        echo "⚠ UNEXPECTED - Received HTTP $HTTP_CODE"
        echo "Response: $RESPONSE_BODY"
        FAILED=$((FAILED + 1))
    fi
    
    echo ""
done

# Cleanup
rm -f /tmp/response_body.txt

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Total Tests: $KEY_COUNT"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed. Please review the results above."
    exit 1
fi
