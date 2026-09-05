<?php

header('Content-Type: application/json');
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}

$date_ = date("Y-m-d h:i:sa");

$user_otp = isset($_POST['Otp']) ? trim($_POST['Otp']) : '';
$referenceNo = isset($_POST['referenceNo']) ? trim($_POST['referenceNo']) : '';

if (empty($user_otp) || empty($referenceNo)) {
    echo json_encode(array(
        'statusCode' => 'FAILED',
        'message' => 'Missing OTP or referenceNo',
        'statusDetail' => 'OTP and reference number are required'
    ));
    exit;
}

// Log OTP verification attempt
try {
    $myfile = fopen("OTP+RefNo.txt", "a+") or die("Unable to open file!");
    fwrite($myfile, "OTP:" . $user_otp . " RefNo:" . $referenceNo . " Date:" . $date_ . "\n");
    fclose($myfile);
} catch (Exception $e) {
    // Continue even if logging fails
}

$requestData = array(
    "applicationId" => "APP_140036",
    "password" => "83bba4667754c412b179d8d84e4ccbae",
    "referenceNo" => $referenceNo,
    "otp" => $user_otp
);

$requestJson = json_encode($requestData);

$url = "https://developer.bdapps.com/subscription/otp/verify";
$ch = curl_init();
curl_setopt($ch, CURLOPT_URL, $url);
curl_setopt($ch, CURLOPT_POST, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, $requestJson);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HTTPHEADER, array(
    "Content-Type: application/json",
    "Content-Length: " . strlen($requestJson)
));
curl_setopt($ch, CURLOPT_TIMEOUT, 15);

$responseJson = curl_exec($ch);

if ($responseJson === false) {
    $error = curl_error($ch);
    curl_close($ch);
    echo json_encode(array(
        'statusCode' => 'FAILED',
        'message' => 'Connection error: ' . $error,
        'statusDetail' => 'Unable to connect to BDApps server'
    ));
    exit;
}

curl_close($ch);

$response = json_decode($responseJson, true);

if ($response === null) {
    echo json_encode(array(
        'statusCode' => 'FAILED',
        'message' => 'Invalid API response',
        'statusDetail' => 'Failed to parse BDApps response',
        'rawResponse' => $responseJson
    ));
    exit;
}

// Return the response from BDApps
echo json_encode(array(
    'statusCode' => isset($response['statusCode']) ? $response['statusCode'] : 'FAILED',
    'statusDetail' => isset($response['statusDetail']) ? $response['statusDetail'] : '',
    'subscriptionStatus' => isset($response['subscriptionStatus']) ? $response['subscriptionStatus'] : '',
    'subscriberId' => isset($response['subscriberId']) ? $response['subscriberId'] : '',
    'version' => isset($response['version']) ? $response['version'] : ''
));

?>