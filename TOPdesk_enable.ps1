#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$auditMessage = " not enabled succesfully";

#TOPdesk system data
$unarchiveUrl = "https://xxxx.topdesk.net/tas/api/persons/id/${aRef}/unarchive"
$updateUrl = "https://xxxx.topdesk.net/tas/api/persons/id/${aRef}"
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
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-Not($dryRun -eq $True)){
 try {
    $response = Invoke-WebRequest -uri $unarchiveUrl -Method PATCH -Headers $headers -UseBasicParsing

    $resp = $response | ConvertFrom-Json

    if(-Not($null -eq $resp.id)) {
        $body = $account | ConvertTo-Json -Depth 10
        $response = Invoke-WebRequest -uri $updateUrl -Method PATCH -Headers $headers -Body $body -UseBasicParsing

        $success = $True;
        $auditMessage = "enabled succesfully";
    }

    }catch{
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $errResponse = $reader.ReadToEnd();
        $auditMessage = " not enabled succesfully: ${errResponse}";
        if($errResponse -like "*Person is already unarchived.*"){
            $success = $True;
            $auditMessage = "enabled succesfully";
        }
    }
}

#build up result
$result = [PSCustomObject]@{ 
	Success= $success;
    AccountReference= $aRef;
	AuditDetails=$auditMessage;
};

Write-Output $result | ConvertTo-Json -Depth 10;