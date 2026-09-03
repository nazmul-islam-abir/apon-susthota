<?php

ini_set('error_log', 'sms-app-error.log');
require 'sdk_file.php';


$appid = "APP_139898";
$apppassword = "d9d75cfad2e4898c070d3df977d10d4c";
$logger = new Logger();

try{
    
    $myfile = fopen("report.txt", "a+") or die("Unable to open file!");
    $unregFile = fopen("unreg.txt", "a+") or die("Unable to open file!");
	// Creating a receiver and intialze it with the incomming data
	$receiver = new SMSReceiver(file_get_contents('php://input'));
	$sender = new SmsSender("https://developer.bdapps.com/sms/send", $appid,$apppassword);
	
	//Creating a sender
	
	$message = $receiver->getMessage(); // Get the message sent to the app
	$address = $receiver->getAddress();	// Get the phone no from which the message was sent 
	
	$sender->setencoding('8');
	$x =$sender->broadcast($message);

	
		file_put_contents("Maskednumber_from_SMS.txt",$address);
      $a = explode(" ", $message);
      $b=" ";
		for($i=1;$i<sizeof($a);$i++)
		{
            $b=$b.' '.$a[$i];
		}
	$message =$b;
    $message = trim($message);
    
    
    

	   
	   
	   
    

	
	
	
	//$logger->WriteLog($receiver->getAddress());
	
//	$address="tel:NTI5ODc4NDdjODBmNGMxZjI5YzMwMDAzZjE1MTMwZjIyYTMzYzRjOTE3ODU0MDVlMmE4ZTBmMjRiMzYyNzgxMTpyb2Jp";


		//---------- 	Send a SMS to a particular user
			$response=$sender->sms("MT: your msg is [".$newMessage."(MO)]- Reaz", $address);
			
				file_put_contents("res.txt",$response);
		//	$response=$sender->sms("MT free msg", $address);
			

    fwrite($myfile,date("Y-m-d",time())." , ". $address ." , ".$message."\n");
    
   //subscription status checking
   
         
    
}


catch(SMSServiceException $e){
	$logger->WriteLog($e->getErrorCode()." ".$e->getErrorMessage()."\n");
}


?>
