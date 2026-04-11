<?php
/**
 * Copy to creds.php (same folder) or use project-root creds.php.
 * Example mysqli connection — match your real creds.php shape.
 */
$conn = new mysqli('localhost', 'user', 'password', 'foodnpals');
if ($conn->connect_error) {
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode(['ok' => false, 'error' => 'Database connection failed']);
    exit;
}
$conn->set_charset('utf8mb4');
