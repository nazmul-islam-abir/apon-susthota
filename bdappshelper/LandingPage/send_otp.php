<?php

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
header('Content-Type: application/json; charset=utf-8'); 

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}
header('Content-Type: application/json; charset=utf-8');

$rawMobile = $_POST['user_mobile'] ?? '';
$digits = preg_replace('/\D+/', '', $rawMobile);

// Accept 018xxxxxxxx, 88018xxxxxxxx, or 8818xxxxxxxx and normalize to 018xxxxxxxx
if (strpos($digits, '880') === 0 && strlen($digits) === 13) {
    $digits = '0' . substr($digits, 3);
} elseif (strpos($digits, '88') === 0 && strlen($digits) === 12) {
    $digits = '0' . substr($digits, 2);
}

// Validate Bangladesh mobile number
if (!preg_match('/^01[3-9][0-9]{8}$/', $digits)) {
    echo json_encode([
        'success' => false,
        'message' => 'Invalid mobile number format',
        'referenceNo' => null
    ]);
    exit;
}

// bdapps subscriberId format
$user_mobile = 'tel:88' . $digits;

// Debug log
file_put_contents('user_number.txt', $user_mobile . PHP_EOL, FILE_APPEND);

// Request data
$requestData = [
    'applicationId' => 'APP_139165',
    'password' => 'b15d29b99fa892ee3bcad0621d08e33f',
    'subscriberId' => $user_mobile,
    'applicationHash' => 'Quiz Shell',
    'applicationMetaData' => [
        'client' => 'MOBILEAPP',
        'device' => 'Samsung S10',
        'os' => 'android 8',
        'appCode' => 'https://play.google.com/store/apps/details?id=lk.dialog.megarunlor'
    ]
];

$requestJson = json_encode($requestData);

// Log the request for debugging
file_put_contents('otp_request.txt', date('Y-m-d H:i:s') . " | Request: " . $requestJson . "\n", FILE_APPEND);

$url = 'https://developer.bdapps.com/subscription/otp/request';
$ch = curl_init();

curl_setopt($ch, CURLOPT_URL, $url);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, $requestJson);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 30);
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Content-Type: application/json',
    'Content-Length: ' . strlen($requestJson)
]);

$responseJson = curl_exec($ch);

if ($responseJson === false) {
    echo json_encode([
        'success' => false,
        'message' => 'cURL error: ' . curl_error($ch),
        'referenceNo' => null
    ]);
    curl_close($ch);
    exit;
}

$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

// Log the raw response for debugging
file_put_contents('otp_response.txt', date('Y-m-d H:i:s') . " | HTTP $httpCode | " . $responseJson . "\n", FILE_APPEND);

// Check if response looks like HTML (error page)
if (stripos($responseJson, '<html') !== false || stripos($responseJson, '<!DOCTYPE') !== false) {
    echo json_encode([
        'success' => false,
        'message' => 'Server returned HTML instead of JSON. HTTP code: ' . $httpCode,
        'referenceNo' => null,
        'rawResponse' => substr($responseJson, 0, 500) // First 500 chars
    ]);
    exit;
}

$response = json_decode($responseJson, true);

if (!is_array($response)) {
    echo json_encode([
        'success' => false,
        'message' => 'Invalid JSON in response',
        'raw' => substr($responseJson, 0, 500), // Show first 500 chars
        'referenceNo' => null,
        'httpCode' => $httpCode
    ]);
    exit;
}

$referenceNo = isset($response['referenceNo']) ? trim((string)$response['referenceNo']) : '';
$statusCode = isset($response['statusCode']) ? (string)$response['statusCode'] : '';
$statusDetail = isset($response['statusDetail']) ? (string)$response['statusDetail'] : '';
$version = isset($response['version']) ? (string)$response['version'] : '';

if ($referenceNo !== '') {
    echo json_encode([
        'success' => true,
        'referenceNo' => $referenceNo,
        'statusCode' => $statusCode,
        'statusDetail' => $statusDetail,
        'version' => $version
    ]);
    exit;
}

echo json_encode([
    'success' => false,
    'message' => $statusDetail !== '' ? $statusDetail : 'OTP reference not returned',
    'referenceNo' => null,
    'statusCode' => $statusCode,
    'statusDetail' => $statusDetail,
    'version' => $version,
    'subscriberId' => $user_mobile
]);