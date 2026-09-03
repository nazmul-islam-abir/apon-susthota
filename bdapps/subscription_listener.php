<?php 

ini_set('error_log', 'ussd-app-error.log');
require 'sdk_file.php';

      
      
date_default_timezone_set("Asia/Dhaka");
$date_= date("Y-m-d h:i:sa");

    
$myfile = fopen("FSubNoti.txt", "a+") or die("Unable to open file!");
 fwrite($myfile,$date_."\n");
    
    


function readSMSNotification() {
    $body = file_get_contents('php://input');
       
    $response = json_decode($body);
       
    $timeStamp = $response->timeStamp;
    $status = $response->status;
    $applicationId = $response->applicationId;
    $subscriberId = $response->subscriberId;
    $frequency = $response->frequency;
    
    $myfile = fopen("FuncSubNoti.txt", "a+") or die("Unable to open file!");
    fwrite($myfile,"TimeStamp:".$timeStamp." |Status:".$status." |App Id:".$applicationId." |SubscriberId".$subscriberId. "\n");
}


readSMSNotification();




        

?>