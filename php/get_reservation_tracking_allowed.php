<?php
/**
 * GET get_reservation_tracking_allowed.php?reservationId=123
 * Authorization: Bearer {LoginToken}
 */
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Authorization, Content-Type');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require_once __DIR__ . '/_include_creds.php';
require_once __DIR__ . '/_auth_bearer.php';

$user = require_bearer_user($conn);
$reservationId = isset($_GET['reservationId']) ? (int) $_GET['reservationId'] : 0;
if ($reservationId <= 0) {
    http_response_code(400);
    echo json_encode(['ok' => false, 'track' => false, 'error' => 'invalid_reservation_id']);
    $conn->close();
    exit;
}

$customerId = (int) $user['UserID'];
$stmt = $conn->prepare(
    'SELECT ReservationID, Status, RestaurantLatitude, RestaurantLongitude FROM reservations WHERE ReservationID = ? AND CustomerID = ? LIMIT 1'
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
$conn->close();

if (!$row) {
    http_response_code(404);
    echo json_encode(['ok' => false, 'track' => false, 'reason' => 'not_found']);
    exit;
}

$status = (string) ($row['Status'] ?? '');
$track = reservation_tracking_allowed($status);
if (!$track) {
    http_response_code(403);
}

$latRaw = $row['RestaurantLatitude'] ?? null;
$lngRaw = $row['RestaurantLongitude'] ?? null;
$restaurantLat = null;
$restaurantLng = null;
if ($latRaw !== null && $latRaw !== '' && is_numeric($latRaw)) {
    $restaurantLat = (float) $latRaw;
}
if ($lngRaw !== null && $lngRaw !== '' && is_numeric($lngRaw)) {
    $restaurantLng = (float) $lngRaw;
}

echo json_encode([
    'ok' => true,
    'track' => $track,
    'status' => $status,
    'restaurantLat' => $restaurantLat,
    'restaurantLng' => $restaurantLng,
]);
