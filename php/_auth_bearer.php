<?php
/**
 * Bearer token auth for tracking APIs.
 * Expects mysqli $conn.
 *
 * Many PHP SAPIs (CGI/FastCGI) do not populate $_SERVER['HTTP_AUTHORIZATION'];
 * mobile clients still send Authorization — read via fallbacks below.
 */
function get_request_authorization_header(): string
{
    if (!empty($_SERVER['HTTP_AUTHORIZATION'])) {
        return (string) $_SERVER['HTTP_AUTHORIZATION'];
    }
    if (!empty($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
        return (string) $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
    }
    if (function_exists('getallheaders')) {
        $headers = @getallheaders();
        if (is_array($headers)) {
            foreach ($headers as $name => $value) {
                if (strcasecmp((string) $name, 'Authorization') === 0) {
                    return (string) $value;
                }
            }
        }
    }
    return '';
}

function require_bearer_user(mysqli $conn): array
{
    $auth = get_request_authorization_header();
    if (!preg_match('/Bearer\s+(\S+)/i', $auth, $m)) {
        http_response_code(401);
        header('Content-Type: application/json');
        echo json_encode(['ok' => false, 'error' => 'missing_bearer_token']);
        exit;
    }
    $token = $m[1];
    $stmt = $conn->prepare('SELECT UserID, Email, LoginToken FROM AppUsers WHERE LoginToken = ? LIMIT 1');
    if (!$stmt) {
        http_response_code(500);
        header('Content-Type: application/json');
        echo json_encode(['ok' => false, 'error' => 'server_error']);
        exit;
    }
    $stmt->bind_param('s', $token);
    $stmt->execute();
    $res = $stmt->get_result();
    $user = $res ? $res->fetch_assoc() : null;
    $stmt->close();
    if (!$user) {
        http_response_code(401);
        header('Content-Type: application/json');
        echo json_encode(['ok' => false, 'error' => 'invalid_token']);
        exit;
    }
    return $user;
}

function reservation_tracking_allowed(string $status): bool
{
    $s = strtolower(trim($status));
    return $s === 'pending' || $s === 'accepted';
}
