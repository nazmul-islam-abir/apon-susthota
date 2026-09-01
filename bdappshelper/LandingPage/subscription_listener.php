<?php
/**
 * BDApps Subscription Listener (incoming callback)
 *
 * BDApps POSTs to this URL whenever a subscriber's status changes
 * (subscription confirmation, daily renewal, unsubscription, etc.).
 *
 * Required behaviour:
 *   1. Respond with HTTP 200 + JSON in the form
 *      { "statusCode": "S1000", "statusDetail": "Success" }
 *   2. Log the payload so we can audit later.
 *   3. The subscription response message (SMS) sent to the user must
 *      include the app's category and the working APK link.
 *
 * The actual SMS body configured at BDApps side is what the user
 * receives — this listener only acks the notification.
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

$APP_ID        = 'NADB26045';
$APP_ID_INTERNAL = 'APP_139165';
$APP_NAME      = 'Amar Diet';
$APP_CATEGORY  = 'Health & Fitness';
$APK_URL       = 'https://bdappsdigitalapps.com/' . $APP_ID . '/apk/amar_diet.apk';
$LOG_FILE      = __DIR__ . '/subscription_listener.log';

$raw = file_get_contents('php://input');
$payload = json_decode($raw, true);
if (!is_array($payload)) {
    $payload = $_POST; // fall back to form-encoded
}

$timeStamp      = $payload['timeStamp']      ?? $payload['timestamp'] ?? '';
$status         = $payload['status']         ?? '';
$applicationId  = $payload['applicationId']  ?? $APP_ID_INTERNAL;
$subscriberId   = $payload['subscriberId']   ?? '';
$frequency      = $payload['frequency']      ?? '';
$statusCode     = $payload['statusCode']     ?? '';
$statusDetail   = $payload['statusDetail']   ?? '';
$subscription   = $payload['subscriptionStatus'] ?? '';

// --- Audit log ---
$line = sprintf(
    "[%s] app=%s sub=%s status=%s subscriptionStatus=%s statusCode=%s detail=%s\n",
    date('Y-m-d H:i:s'),
    $applicationId,
    $subscriberId,
    $status,
    $subscription,
    $statusCode,
    $statusDetail
);
@file_put_contents($LOG_FILE, $line, FILE_APPEND);

// --- Autosave / logout hint ---
// BDApps sends status="UNREGISTERED" when the user USSDs *123*5#.
// We can't log them out from the server side, but we record the event
// so the app (on next open) can poll check_subscription.php and force-
// logout.  The app's own unsubscribe flow also calls signOut() locally.
if (strtoupper($status) === 'UNREGISTERED' || strtoupper($subscription) === 'UNREGISTERED') {
    $ev = sprintf("[%s] UNSUBSCRIBE notified for %s\n", date('Y-m-d H:i:s'), $subscriberId);
    @file_put_contents($LOG_FILE, $ev, FILE_APPEND);
}

// --- Always respond success so BDApps doesn't retry ---
$response = [
    'statusCode'   => 'S1000',
    'statusDetail' => 'Success',
    'applicationId'   => $APP_ID_INTERNAL,
    'category'        => $APP_CATEGORY,
    'appDownloadLink' => $APK_URL,
];
echo json_encode($response);
