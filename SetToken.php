<?php
//flutter run -d 12778374A5100738
// SetToken.php

include 'creds.php'; // DB connection
header('Content-Type: application/json');

$email = $_GET['email'] ?? null;
$token = $_GET['token'] ?? null;

if (!$email || !$token) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'Missing email or token']);
    exit();
}

$stmt = $conn->prepare("UPDATE AppUsers SET LoginToken = ? WHERE Email = ?");
$stmt->bind_param("ss", $token, $email);
$stmt->execute();

if ($stmt->affected_rows > 0) {
    echo json_encode(['status' => 'success', 'message' => 'Token updated']);
} else {
    // Extract names from email
    $username = $email;
    $parts = explode('@', $email);
    $firstName = ucfirst($parts[0]);
    $lastName =  ucfirst($parts[0]);

    $latitude = "42.3314";  // Michigan USA
    $longitude = "-83.0458";

    $accountStatus = "Pending";
    $userType = "User";
    $registrationDate = date("Y-m-d H:i:s");

    $insertStmt = $conn->prepare("
        INSERT INTO AppUsers 
        (FirstName, LastName, Email, Username, LoginToken, Latitude, Longitude, AccountStatus, UserType, RegistrationDate) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ");
    $insertStmt->bind_param("ssssssssss", 
        $firstName, 
        $lastName, 
        $email, 
        $username, 
        $token, 
        $latitude, 
        $longitude, 
        $accountStatus, 
        $userType, 
        $registrationDate
    );

    if ($insertStmt->execute()) {
        echo json_encode(['status' => 'success', 'message' => 'New user created']);
    } else {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => 'Failed to create new user']);
    }

    $insertStmt->close();
}

$stmt->close();
$conn->close();
