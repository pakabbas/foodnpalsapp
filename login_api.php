<?php

// Hide errors from output, log them instead
ini_set('display_errors', 0);
ini_set('log_errors', 1);
ini_set('error_log', 'php_error.log');
error_reporting(E_ALL);

// Headers
header("Content-Type: application/json");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST");

include 'creds.php';

// Support both GET and POST
$data = $_SERVER['REQUEST_METHOD'] === 'POST'
    ? json_decode(file_get_contents("php://input"), true)
    : $_GET;

$usernameOrEmail = $data['username'] ?? '';
$password = $data['password'] ?? '';
$token = $data['token'] ?? '';

if (empty($usernameOrEmail) || empty($password) || empty($token)) {
    echo json_encode(["success" => false, "message" => "Missing credentials or token"]);
    exit();
}

$sql = "SELECT * FROM AppUsers WHERE Username = ? OR Email = ?";
$stmt = $conn->prepare($sql);
$stmt->bind_param("ss", $usernameOrEmail, $usernameOrEmail);
$stmt->execute();
$result = $stmt->get_result();

if ($result && $result->num_rows > 0) {
    $user = $result->fetch_assoc();

    if (password_verify($password, $user['Password'])) {
        $update = $conn->prepare("UPDATE AppUsers SET LoginToken = ? WHERE UserID = ?");
        $update->bind_param("si", $token, $user['UserID']);
        $update->execute();
        $update->close();

        unset($user['Password']);
        $user['LoginToken'] = $token;

        echo json_encode([
            "success" => true,
            "message" => "Login successful",
            "user" => $user
        ]);
    } else {
        echo json_encode(["success" => false, "message" => "Invalid password"]);
    }
} else {
    echo json_encode(["success" => false, "message" => "User not found"]);
}

$stmt->close();
$conn->close();
