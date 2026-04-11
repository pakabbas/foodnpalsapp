<?php
/**
 * Loads project-root creds.php (same DB as the rest of foodnpals.com).
 * Sets $isJson so creds.php returns JSON on connection failure instead of silent fail.
 */
$isJson = true;

$rootCreds = dirname(__DIR__) . '/creds.php';
if (!is_readable($rootCreds)) {
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode(['ok' => false, 'error' => 'database_config_missing', 'message' => 'creds.php not found in project root']);
    exit;
}

require_once $rootCreds;

if (!isset($conn) || !($conn instanceof mysqli)) {
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode(['ok' => false, 'error' => 'database_connection_failed']);
    exit;
}

if ($conn->connect_error) {
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode(['ok' => false, 'error' => 'database_connection_failed']);
    exit;
}

$conn->set_charset('utf8mb4');
