#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json
$auditMessage = " not created succesfully";

#TOPdesk system data
$url = 'https://xxxx.topdesk.net/tas/api/persons'
$apiKey = 'xxxx-xxxx-xxxx-xxxx-xxxx'
$userName = 'xxxx'
$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json' }

#mapping
$username = $p.ExternalID;

$account = @{
    surName = $p.Name.FamilyName;
    firstName = $p.Name.NickName;
    firstInitials = $p.Name.Initials;
    birthName = $p.Name.FamilyName;
    employeeNumber = $p.ExternalID;
    jobTitle = $p.PrimaryContract.Title.Name;
    email = $p.Contact.Business.Email;
    networkLoginName = $username;
    tasLoginName = $username;
    branch = @{ id ='1fe19024-d652-46ec-b080-eec3737a3d7a'};
}

#correlation
$correlationField = 'employeeNumber';
$correlationValue = $p.ExternalID;

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-Not($dryRun -eq $True)){
 try {
    $create = $True;
    $correlationUrl = $url + "?page_size=2&query=$($correlationField)=='$($correlationValue)'"
    $response = Invoke-WebRequest -uri $correlationUrl -Method Get -Headers $headers -UseBasicParsing
    $resp = $response | ConvertFrom-Json

    if(-Not($null -eq $resp) -and -Not($null -eq $resp[0].id)) {
        $aRef = $resp[0].id 
        $create = $False;
        $success = $True;
        $auditMessage = "Correlation found record $($correlationValue) update succesfully";
    }
   
    if($create){
        $body = $account | ConvertTo-Json -Depth 10
        $response = Invoke-WebRequest -uri $url -Method POST -Headers $headers -Body $body -UseBasicParsing
        $resp = $response | ConvertFrom-Json

        if(-Not($null -eq $resp.id)){
            $aRef = $resp.id 
            $success = $True;
            $auditMessage = "created succesfully";
        }
    }

    }catch{
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $errResponse = $reader.ReadToEnd();
        $auditMessage = " not created succesfully: ${errResponse}";
    }
}

#build up result
$result = [PSCustomObject]@{ 
	Success= $success;
    AccountReference= $aRef;
	AuditDetails=$auditMessage;
    Account= $account;
};

Write-Output $result | ConvertTo-Json -Depth 10;