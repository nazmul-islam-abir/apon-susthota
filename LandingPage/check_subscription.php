<?php

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
header("Content-Type: application/json");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}


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
        'error' => 'Invalid mobile number format',
        'providedNumber' => $rawMobile
    ]);
    exit;
}

// bdapps subscriberId format
$subscriberId = 'tel:88' . $digits;

$requestData = [
    'version' => '1.0',
    'applicationId' => 'APP_139898',
    'password' => 'd9d75cfad2e4898c070d3df977d10d4c',
    'subscriberId' => $subscriberId,
];

$requestJson = json_encode($requestData);

// BDApps subscription status API
$url = 'https://developer.bdapps.com/subscription/getStatus';
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $url);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, $requestJson);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 10);
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Content-Type: application/json',
    'Content-Length: ' . strlen($requestJson),
]);

$responseJson = curl_exec($ch);
$curlError = curl_error($ch);
curl_close($ch);

if ($responseJson === false) {
    echo json_encode([
        'error' => 'cURL failed',
        'details' => $curlError,
    ]);
    exit;
}

$response = json_decode($responseJson, true);
if (!is_array($response)) {
    echo json_encode(['error' => 'Invalid response']);
    exit;
}

$status = strtoupper(trim($response['subscriptionStatus'] ?? ''));

// Per getStatus contract, subscription status is REGISTERED or UNREGISTERED.
$isSubscribed = ($status === 'REGISTERED');

echo json_encode([
    'subscriptionStatus' => $status,
    'isSubscribed' => $isSubscribed,
    'statusCode' => $response['statusCode'] ?? null,
    'statusDetail' => $response['statusDetail'] ?? null,
    'version' => $response['version'] ?? null,
    'subscriberId' => $subscriberId
]);
?>
