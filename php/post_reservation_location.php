<?php
/**
 * POST post_reservation_location.php?reservationId=123
 * Authorization: Bearer {LoginToken}
 * Body JSON: { "lat", "lng", "accuracy", "arrived", "timestamp" }
 *
 * Updates CustomerLatitude, CustomerLongitude when Status is Pending or Accepted (case-insensitive).
 */
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require_once __DIR__ . '/_include_creds.php';
require_once __DIR__ . '/_auth_bearer.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['ok' => false, 'track' => false, 'error' => 'method_not_allowed']);
    $conn->close();
    exit;
}

$user = require_bearer_user($conn);
$reservationId = isset($_GET['reservationId']) ? (int) $_GET['reservationId'] : 0;
if ($reservationId <= 0) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'track' => false, 'error' => 'invalid_reservation_id']);
    $conn->close();
    exit;
}

$raw = file_get_contents('php://input');
$body = json_decode($raw ?: '[]', true);
if (!is_array($body)) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'track' => false, 'error' => 'invalid_json']);
    $conn->close();
    exit;
}

$lat = isset($body['lat']) ? (float) $body['lat'] : null;
$lng = isset($body['lng']) ? (float) $body['lng'] : null;
if ($lat === null || $lng === null) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'track' => false, 'error' => 'missing_lat_lng']);
    $conn->close();
    exit;
}

$accuracy = isset($body['accuracy']) ? (float) $body['accuracy'] : null;
$arrived = !empty($body['arrived']);

$customerId = (int) $user['UserID'];
$stmt = $conn->prepare(
    'SELECT ReservationID, Status FROM reservations WHERE ReservationID = ? AND CustomerID = ? LIMIT 1'
);
if (!$stmt) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'track' => false, 'error' => 'server_error']);
    $conn->close();
    exit;
}
$stmt->bind_param('ii', $reservationId, $customerId);
$stmt->execute();
$row = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$row) {
    http_response_code(404);
    echo json_encode(['ok' => false, 'track' => false, 'reason' => 'not_found']);
    $conn->close();
    exit;
}

$status = (string) ($row['Status'] ?? '');
if (!reservation_tracking_allowed($status)) {
    http_response_code(403);
    echo json_encode(['ok' => false, 'track' => false, 'reason' => 'invalid_status']);
    $conn->close();
    exit;
}

$latStr = (string) $lat;
$lngStr = (string) $lng;
$upd = $conn->prepare(
    'UPDATE reservations SET CustomerLatitude = ?, CustomerLongitude = ?, UpdateCounter = UpdateCounter + 1 WHERE ReservationID = ? AND CustomerID = ?'
);
if (!$upd) {
    // DB without UpdateCounter column — fall back to lat/lng only.
    $upd = $conn->prepare(
        'UPDATE reservations SET CustomerLatitude = ?, CustomerLongitude = ? WHERE ReservationID = ? AND CustomerID = ?'
    );
}
if (!$upd) {
    http_response_code(500);
    echo json_encode(['ok' => false, 'track' => false, 'error' => 'server_error']);
    $conn->close();
    exit;
}
$upd->bind_param('ssii', $latStr, $lngStr, $reservationId, $customerId);
$upd->execute();
$upd->close();

$updateCounter = null;
$cntStmt = $conn->prepare('SELECT UpdateCounter FROM reservations WHERE ReservationID = ? AND CustomerID = ? LIMIT 1');
if ($cntStmt) {
    $cntStmt->bind_param('ii', $reservationId, $customerId);
    $cntStmt->execute();
    $cntRow = $cntStmt->get_result()->fetch_assoc();
    $cntStmt->close();
    if ($cntRow && isset($cntRow['UpdateCounter'])) {
        $updateCounter = (int) $cntRow['UpdateCounter'];
    }
}

$conn->close();

echo json_encode([
    'ok' => true,
    'track' => true,
    'arrived' => $arrived,
    'accuracy_saved' => $accuracy,
    'updateCounter' => $updateCounter,
]);
