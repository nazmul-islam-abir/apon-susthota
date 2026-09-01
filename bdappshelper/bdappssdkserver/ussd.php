<?php

ini_set('error_log', 'ussd-app-error.log');
require 'sdk_file.php';
$date_= date("Y-m-d h:i:sa");

$appid = "APP_139165";
$apppassword = "b15d29b99fa892ee3bcad0621d08e33f";

$sender = new SmsSender("https://developer.bdapps.com/sms/send", $appid,$apppassword);

//file_put_contents('ussd.txt',$_SERVER['REMOTE_ADDR']);

$production=true;

	if($production==false){
		$ussdserverurl ='http://localhost:7000/ussd/send';
	}
	else{
		$ussdserverurl= 'https://developer.bdapps.com/ussd/send';
	}

try{
$receiver 	= new UssdReceiver();
$ussdSender = new UssdSender($ussdserverurl,$appid,$apppassword);
$subscription = new Subscription('https://developer.bdapps.com/subscription/send',$apppassword,$appid);
// file_put_contents('text.txt',$receiver->getRequestID());
// $operations = new Operations();

//$receiverSessionId  =   $receiver->getSessionId();
$content 			= 	$receiver->getMessage(); // get the message content
$address 			= 	$receiver->getAddress(); // get the ussdSender's address
$requestId 			= 	$receiver->getRequestID(); // get the request ID
$applicationId 		= 	$receiver->getApplicationId(); // get application ID
$encoding 			=	$receiver->getEncoding(); // get the encoding value
$version 			= 	$receiver->getVersion(); // get the version
$sessionId 			= 	$receiver->getSessionId(); // get the session ID;
$ussdOperation 		= 	$receiver->getUssdOperation(); // get the ussd operation

$status = $subscription->getStatus($address);


try{
    $myfile = fopen("MaskNumbers_from_USSD.txt", "a+") or die("Unable to open file!");
    fwrite($myfile,$address." Date".$date_."\n");
}
catch(Exception $e){
    
}

try{
    $myfile = fopen("USSD msg.txt", "a+") or die("Unable to open file!");
    fwrite($myfile,$content."\n");
}
catch(Exception $e){
    
}

//$response=$sender->sms('This message is for MT testing, So MT works[Reaz]', $address);

 $responseMsg = ($status == "REGISTERED")? "1. unsubscribe" : "Please wait for the confirmation pop-up.";


if ($ussdOperation  == "mo-init") {
  if($status == "REGISTERED"){
	   try {
		$ussdSender->ussd($sessionId, $responseMsg,$address);

	    } catch (Exception $e) {
			$ussdSender->ussd($sessionId, 'Sorry error occured try again',$address );
	    }
  }
  else {
	   
		try {
		    
		    
		  $ussdSender->ussd($sessionId, $responseMsg,$address,'mt-fin');

		    $x = $subscription->subscribe($address);

		} catch (Exception $e) {
				$ussdSender->ussd($sessionId, 'Sorry error occured try again',$address );
		}
  }
	
}

}
catch (Exception $e){
 file_put_contents('USSDERROR.txt','Some error occured');   
}
?>


