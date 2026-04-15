<?php
/**
 * Configuration file for POC Key Management Dashboard
 */

// DynamoDB Configuration
define('TABLE_NAME', 'POC-KeyValidation');
define('AWS_REGION', 'us-east-1');

// AWS SDK Path - Update this if you install AWS SDK in a different location
// The SDK will be loaded via Composer autoload
define('AWS_SDK_PATH', __DIR__ . '/vendor/autoload.php');

// Load AWS SDK via Composer autoload
if (!file_exists(AWS_SDK_PATH)) {
    die('AWS SDK not found. Run "composer require aws/aws-sdk-php" in the html/ directory.');
}
require_once AWS_SDK_PATH;

// Error reporting (set to 0 in production)
error_reporting(E_ALL);
ini_set('display_errors', 1);

// Timezone
date_default_timezone_set('America/Los_Angeles');
