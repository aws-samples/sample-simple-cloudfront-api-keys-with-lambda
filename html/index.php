<?php
/**
 * POC Key Management Dashboard
 * Manages API keys stored in DynamoDB
 */

require_once 'config.php';
require_once 'functions.php';

// Handle form submissions
$message = '';
$messageType = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['action'])) {
        switch ($_POST['action']) {
            case 'add':
                $result = addKey($_POST['keyid'], $_POST['keyvalue'], $_POST['customer']);
                $message = $result['message'];
                $messageType = $result['success'] ? 'success' : 'error';
                break;
            
            case 'toggle':
                $result = toggleKeyState($_POST['keyid'], $_POST['state']);
                $message = $result['message'];
                $messageType = $result['success'] ? 'success' : 'error';
                break;
            
            case 'delete':
                $result = deleteKey($_POST['keyid']);
                $message = $result['message'];
                $messageType = $result['success'] ? 'success' : 'error';
                break;
        }
    }
}

// Get all keys from DynamoDB
$keys = getAllKeys();
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>POC Key Management Dashboard</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <header>
            <h1>🔐 POC Key Management Dashboard</h1>
            <p>Manage CloudFront authentication keys</p>
        </header>

        <?php if ($message): ?>
            <div class="message <?php echo $messageType; ?>">
                <?php echo htmlspecialchars($message); ?>
            </div>
        <?php endif; ?>

        <!-- Add New Key Form -->
        <section class="add-key-section">
            <h2>Add New Key</h2>
            <form method="POST" action="" class="add-key-form">
                <input type="hidden" name="action" value="add">
                
                <div class="form-group">
                    <label for="keyid">Key ID:</label>
                    <input type="text" id="keyid" name="keyid" required 
                           placeholder="e.g., customer-key-001"
                           pattern="[a-zA-Z0-9\-_]+"
                           title="Only letters, numbers, hyphens, and underscores allowed">
                </div>

                <div class="form-group">
                    <label for="keyvalue">Key Value:</label>
                    <input type="text" id="keyvalue" name="keyvalue" required 
                           placeholder="e.g., secret-value-001"
                           minlength="8">
                </div>

                <div class="form-group">
                    <label for="customer">Customer Name:</label>
                    <input type="text" id="customer" name="customer" required 
                           placeholder="e.g., Acme Corporation">
                </div>

                <button type="submit" class="btn btn-primary">Add Key</button>
            </form>
        </section>

        <!-- Keys Table -->
        <section class="keys-section">
            <h2>Existing Keys (<?php echo count($keys); ?>)</h2>
            
            <?php if (empty($keys)): ?>
                <p class="no-keys">No keys found. Add your first key above.</p>
            <?php else: ?>
                <div class="table-responsive">
                    <table class="keys-table">
                        <thead>
                            <tr>
                                <th>Key ID</th>
                                <th>Key Value</th>
                                <th>Customer</th>
                                <th>Status</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php foreach ($keys as $key): ?>
                                <tr class="<?php echo $key['State'] === 'Active' ? 'active' : 'disabled'; ?>">
                                    <td class="key-id">
                                        <code><?php echo htmlspecialchars($key['KeyID']); ?></code>
                                    </td>
                                    <td class="key-value">
                                        <code><?php echo htmlspecialchars($key['KeyValue']); ?></code>
                                    </td>
                                    <td><?php echo htmlspecialchars($key['Customer']); ?></td>
                                    <td>
                                        <form method="POST" action="" class="inline-form">
                                            <input type="hidden" name="action" value="toggle">
                                            <input type="hidden" name="keyid" value="<?php echo htmlspecialchars($key['KeyID']); ?>">
                                            <input type="hidden" name="state" value="<?php echo $key['State'] === 'Active' ? 'Disabled' : 'Active'; ?>">
                                            
                                            <label class="switch">
                                                <input type="checkbox" 
                                                       <?php echo $key['State'] === 'Active' ? 'checked' : ''; ?>
                                                       onchange="this.form.submit()">
                                                <span class="slider"></span>
                                            </label>
                                            <span class="status-label <?php echo strtolower($key['State']); ?>">
                                                <?php echo $key['State']; ?>
                                            </span>
                                        </form>
                                    </td>
                                    <td>
                                        <form method="POST" action="" class="inline-form" 
                                              onsubmit="return confirm('Are you sure you want to delete this key?');">
                                            <input type="hidden" name="action" value="delete">
                                            <input type="hidden" name="keyid" value="<?php echo htmlspecialchars($key['KeyID']); ?>">
                                            <button type="submit" class="btn btn-danger btn-small">Delete</button>
                                        </form>
                                    </td>
                                </tr>
                            <?php endforeach; ?>
                        </tbody>
                    </table>
                </div>
            <?php endif; ?>
        </section>

        <footer>
            <p>POC Key Management Dashboard | DynamoDB Table: <code><?php echo TABLE_NAME; ?></code></p>
        </footer>
    </div>
</body>
</html>
