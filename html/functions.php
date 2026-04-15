<?php
/**
 * Functions for interacting with DynamoDB
 * Uses the AWS SDK for PHP (installed via Composer)
 */

use Aws\DynamoDb\DynamoDbClient;
use Aws\DynamoDb\Exception\DynamoDbException;
use Aws\DynamoDb\Marshaler;

/**
 * Get a singleton DynamoDbClient instance
 */
function getDynamoDbClient(): DynamoDbClient {
    static $client = null;

    if ($client === null) {
        $client = new DynamoDbClient([
            'region'  => AWS_REGION,
            'version' => 'latest',
        ]);
    }

    return $client;
}

/**
 * Get all keys from DynamoDB
 */
function getAllKeys(): array {
    $client = getDynamoDbClient();
    $marshaler = new Marshaler();

    try {
        $result = $client->scan([
            'TableName' => TABLE_NAME,
        ]);
    } catch (DynamoDbException $e) {
        error_log('DynamoDB scan error: ' . $e->getMessage());
        return [];
    }

    $items = $result['Items'] ?? [];
    $keys = [];

    foreach ($items as $item) {
        $data = $marshaler->unmarshalItem($item);
        $keys[] = [
            'KeyID'    => $data['KeyID'] ?? '',
            'KeyValue' => $data['KeyValue'] ?? '',
            'State'    => $data['State'] ?? 'Disabled',
            'Customer' => $data['Customer'] ?? '',
        ];
    }

    usort($keys, fn($a, $b) => strcmp($a['KeyID'], $b['KeyID']));

    return $keys;
}

/**
 * Add a new key to DynamoDB
 */
function addKey(string $keyId, string $keyValue, string $customer): array {
    if (empty($keyId) || empty($keyValue) || empty($customer)) {
        return ['success' => false, 'message' => 'All fields are required'];
    }

    // Check if key already exists
    $client = getDynamoDbClient();
    $marshaler = new Marshaler();

    try {
        $existing = $client->getItem([
            'TableName' => TABLE_NAME,
            'Key' => $marshaler->marshalItem(['KeyID' => $keyId]),
        ]);

        if (!empty($existing['Item'])) {
            return ['success' => false, 'message' => 'Key ID already exists'];
        }
    } catch (DynamoDbException $e) {
        return ['success' => false, 'message' => 'Error checking key: ' . $e->getMessage()];
    }

    try {
        $client->putItem([
            'TableName' => TABLE_NAME,
            'Item' => $marshaler->marshalItem([
                'KeyID'    => $keyId,
                'KeyValue' => $keyValue,
                'State'    => 'Active',
                'Customer' => $customer,
            ]),
        ]);
    } catch (DynamoDbException $e) {
        return ['success' => false, 'message' => 'Error adding key: ' . $e->getMessage()];
    }

    return ['success' => true, 'message' => 'Key added successfully'];
}

/**
 * Toggle key state between Active and Disabled
 */
function toggleKeyState(string $keyId, string $newState): array {
    if (!in_array($newState, ['Active', 'Disabled'], true)) {
        return ['success' => false, 'message' => 'Invalid state'];
    }

    $client = getDynamoDbClient();
    $marshaler = new Marshaler();

    try {
        $client->updateItem([
            'TableName' => TABLE_NAME,
            'Key' => $marshaler->marshalItem(['KeyID' => $keyId]),
            'UpdateExpression' => 'SET #state = :newstate',
            'ExpressionAttributeNames'  => ['#state' => 'State'],
            'ExpressionAttributeValues' => $marshaler->marshalItem([':newstate' => $newState]),
        ]);
    } catch (DynamoDbException $e) {
        return ['success' => false, 'message' => 'Error updating key: ' . $e->getMessage()];
    }

    return ['success' => true, 'message' => 'Key state updated to ' . $newState];
}

/**
 * Delete a key from DynamoDB
 */
function deleteKey(string $keyId): array {
    $client = getDynamoDbClient();
    $marshaler = new Marshaler();

    try {
        $client->deleteItem([
            'TableName' => TABLE_NAME,
            'Key' => $marshaler->marshalItem(['KeyID' => $keyId]),
        ]);
    } catch (DynamoDbException $e) {
        return ['success' => false, 'message' => 'Error deleting key: ' . $e->getMessage()];
    }

    return ['success' => true, 'message' => 'Key deleted successfully'];
}

/**
 * Get statistics about keys
 */
function getKeyStats(): array {
    $keys = getAllKeys();

    $stats = [
        'total'    => count($keys),
        'active'   => 0,
        'disabled' => 0,
    ];

    foreach ($keys as $key) {
        if ($key['State'] === 'Active') {
            $stats['active']++;
        } else {
            $stats['disabled']++;
        }
    }

    return $stats;
}
