# POC Key Management Dashboard

A PHP web application for managing CloudFront authentication keys stored in DynamoDB.

## Features

- 📋 **View All Keys** - Display all API keys with their details
- ➕ **Add New Keys** - Create new authentication keys
- 🔄 **Toggle Status** - Enable/disable keys with a simple toggle switch
- 🗑️ **Delete Keys** - Remove keys from the system
- 🎨 **Modern UI** - Clean, responsive interface

## Requirements

- PHP 7.4 or higher
- AWS CLI configured with appropriate credentials
- EC2 instance with IAM role that has DynamoDB permissions
- Apache or Nginx web server

## Installation

### 1. Deploy to EC2 Instance

Copy the `html` folder to your web server directory:

```bash
# For Apache on Amazon Linux 2
sudo cp -r html/* /var/www/html/

# Set proper permissions
sudo chown -R apache:apache /var/www/html/
sudo chmod -R 755 /var/www/html/
```

### 2. Configure EC2 IAM Role

Ensure your EC2 instance has an IAM role with the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:Scan",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:*:table/POC-KeyValidation"
    }
  ]
}
```

### 3. Install and Configure Apache (if not already installed)

```bash
# Install Apache and PHP
sudo yum install -y httpd php

# Start Apache
sudo systemctl start httpd
sudo systemctl enable httpd

# Configure firewall (if needed)
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload
```

### 4. Verify AWS CLI Access

Test that the EC2 instance can access DynamoDB:

```bash
aws dynamodb scan --table-name POC-KeyValidation --region us-east-1
```

## Configuration

Edit `config.php` to customize settings:

```php
// DynamoDB Configuration
define('TABLE_NAME', 'POC-KeyValidation');
define('AWS_REGION', 'us-east-1');
```

## Usage

### Access the Dashboard

Open your browser and navigate to:
```
http://your-ec2-public-ip/
```

### Add a New Key

1. Fill in the form at the top of the page:
   - **Key ID**: Unique identifier (e.g., `customer-key-001`)
   - **Key Value**: Secret value (minimum 8 characters)
   - **Customer Name**: Name of the customer
2. Click "Add Key"
3. The key will be created with "Active" status by default

### Toggle Key Status

- Click the toggle switch next to any key to enable/disable it
- Active keys will authenticate successfully
- Disabled keys will return 401 errors

### Delete a Key

- Click the "Delete" button next to any key
- Confirm the deletion when prompted
- The key will be permanently removed from DynamoDB

## File Structure

```
html/
├── index.php       # Main dashboard page
├── config.php      # Configuration settings
├── functions.php   # DynamoDB interaction functions
├── style.css       # Stylesheet
└── README.md       # This file
```

## Security Considerations

### Production Deployment

1. **Use HTTPS**: Configure SSL/TLS certificates
   ```bash
   sudo yum install -y mod_ssl
   # Configure SSL certificate
   ```

2. **Restrict Access**: Use security groups to limit access
   - Only allow specific IP addresses
   - Use VPN or bastion host

3. **Add Authentication**: Implement user authentication
   - Use Apache .htaccess
   - Implement PHP session-based auth
   - Consider AWS Cognito integration

4. **Disable Error Display**: In production, set in `config.php`:
   ```php
   error_reporting(0);
   ini_set('display_errors', 0);
   ```

5. **Input Validation**: The application includes basic validation, but consider:
   - Rate limiting
   - CSRF protection
   - Additional input sanitization

## Troubleshooting

### "No keys found" message

- Verify DynamoDB table exists: `aws dynamodb describe-table --table-name POC-KeyValidation --region us-east-1`
- Check IAM role permissions on EC2 instance
- Verify AWS CLI is configured: `aws sts get-caller-identity`

### Permission Denied Errors

- Check file permissions: `ls -la /var/www/html/`
- Ensure Apache user can execute AWS CLI: `sudo -u apache aws sts get-caller-identity`
- Verify IAM role is attached to EC2 instance

### PHP Errors

- Check Apache error logs: `sudo tail -f /var/log/httpd/error_log`
- Verify PHP is installed: `php --version`
- Check PHP error logs: `sudo tail -f /var/log/php-fpm/error.log`

### AWS CLI Not Found

- Install AWS CLI: `sudo yum install -y aws-cli`
- Verify installation: `which aws`

## API Reference

### Functions (functions.php)

#### `getAllKeys()`
Returns an array of all keys from DynamoDB.

#### `addKey($keyId, $keyValue, $customer)`
Adds a new key to DynamoDB.
- Returns: `['success' => bool, 'message' => string]`

#### `toggleKeyState($keyId, $newState)`
Updates the state of a key (Active/Disabled).
- Returns: `['success' => bool, 'message' => string]`

#### `deleteKey($keyId)`
Deletes a key from DynamoDB.
- Returns: `['success' => bool, 'message' => string]`

## Integration with CloudFront

Keys managed through this dashboard are automatically used by the Lambda@Edge function attached to your CloudFront distribution. Changes take effect immediately:

- **Adding a key**: Immediately available for authentication
- **Disabling a key**: Immediately blocks authentication
- **Deleting a key**: Immediately removes authentication capability

## Support

For issues related to:
- **DynamoDB**: Check AWS DynamoDB documentation
- **EC2/IAM**: Check AWS IAM and EC2 documentation
- **Apache/PHP**: Check Apache and PHP documentation

## License

This is a proof-of-concept implementation. Modify as needed for production use.
