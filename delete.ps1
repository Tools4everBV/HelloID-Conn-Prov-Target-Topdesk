#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$auditMessage = " not updated succesfully";

#TOPdesk system data
$urlUpdate = "https://xxxx.topdesk.net/tas/api/persons/id/${aRef}"
$urlUnarchive = "https://xxxx.topdesk.net/tas/api/persons/id/${aRef}/unarchive"
$urlArchive = "https://xxxx.topdesk.net/tas/api/persons/id/${aRef}/archive"
$apiKey = 'xxxx-xxxx-xxxx-xxxx'
$userName = 'xxxx'
$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json' }

#mapping
$account = @{
    networkLoginName = '';
    tasLoginName = '';
    email = '';
}

$archive = @{
    id = "64d2d84d-de01-5bc4-bf4a-08ec61e20d1e"; 
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$continue = $True
if(-Not($dryRun -eq $True)){
    if($continue){
        try{
            Invoke-WebRequest -uri $urlUnarchive -Method PATCH -Headers $headers -UseBasicParsing | Out-Null
        }catch{
            $result = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($result)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $errResponse = $reader.ReadToEnd();
            $auditMessage = " not enabled succesfully: ${errResponse}";
            $continue = $False
            if($errResponse -like "*Person is already unarchived.*"){
                $continue = $True
            }
        }
    }

    if($continue){
        try{
            $body = $account | ConvertTo-Json -Depth 10
            Invoke-WebRequest -uri $urlUpdate -Method PATCH -Headers $headers -Body $body -UseBasicParsing | Out-Null
        }catch{
            $result = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($result)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $errResponse = $reader.ReadToEnd();
            $continue = $False
            $auditMessage = " not deleted succesfully: ${errResponse}";
        }
    }
    if($continue){
        try {
            $body = $archive | ConvertTo-Json -Depth 10
            Invoke-WebRequest -uri $urlArchive -Method PATCH -Headers $headers -Body $body -UseBasicParsing | Out-Null
        }catch{
            Write-verbose $response -Verbose
            $result = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($result)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $errResponse = $reader.ReadToEnd();
            $continue = $False
            $auditMessage = " not deleted succesfully: ${errResponse}";
        }
    }
}
if($continue){
    $auditMessage = " deleted succesfully";
    $success = $True;
}else{
    $success = $False;
}

#build up result
$result = [PSCustomObject]@{ 
	Success= $success;
    AccountReference= $aRef;
	AuditDetails=$auditMessage;
};

Write-Output $result | ConvertTo-Json -Depth 10;