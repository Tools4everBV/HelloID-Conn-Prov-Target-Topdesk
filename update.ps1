#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$auditMessage = " not updated succesfully";

#TOPdesk system data
$url = "https://xxxx.topdesk.net/tas/api/persons/id/${aRef}"
$apiKey = 'xxxx-xxxx-xxxx-xxxx'
$userName = 'xxxx'
$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json' }

#mapping
$account = @{
    surName = $p.Name.FamilyName;
    firstName = $p.Name.NickName;
    firstInitials = $p.Name.Initials;
    birthName = $p.Name.FamilyName;
    employeeNumber = $p.ExternalID;
    jobTitle = $p.PrimaryContract.Title.Name;
    email = $p.Contact.Business.Email;
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-Not($dryRun -eq $True)){
 try {
   
    $body = $account | ConvertTo-Json -Depth 10
    $response = Invoke-WebRequest -uri $url -Method PATCH -Headers $headers -Body $body -UseBasicParsing
    
    $resp = $response | ConvertFrom-Json
    
    if(-Not($null -eq $resp.id)) {
        $success = $True;
        $auditMessage = "updated succesfully";
    }

    }catch{
        Write-verbose $response -Verbose
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $errResponse = $reader.ReadToEnd();
        $auditMessage = " not updated succesfully: ${errResponse}";
    }

}
#build up result
$result = [PSCustomObject]@{ 
	Success= $success;
    AccountReference= $aRef;
	AuditDetails=$auditMessage;
};

Write-Output $result | ConvertTo-Json -Depth 10;