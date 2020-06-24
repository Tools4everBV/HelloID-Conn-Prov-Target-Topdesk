#Initialize default properties
$success = $False;
$aRef = $accountReference | ConvertFrom-Json
$auditMessage = " not enabled succesfully";

#TOPdesk system data
$url = "https://xxxx.topdesk.net/tas/api/persons/id/${aRef}/archive"
$apiKey = 'xxxx-xxxx-xxxx-xxxx-xxxx'
$userName = 'xxxx'
$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json' }

$archive = @{
      id = "64d2d84d-de01-5bc4-bf4a-08ec61e20d1e"; 
}


[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-Not($dryRun -eq $True)){
 try {
    $body = $archive | ConvertTo-Json -Depth 10
    $response = Invoke-WebRequest -uri $url -Method PATCH -Headers $headers -Body $body -UseBasicParsing

    $resp = $response | ConvertFrom-Json

    if(-Not($null -eq $resp.id)) {
        $success = $True;
        $auditMessage = "disabled succesfully";
    }

    }catch{
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $errResponse = $reader.ReadToEnd();
        $auditMessage = " not disabled succesfully: ${errResponse}";
        if($errResponse -like "*Person is already archived.*"){
            $success = $True;
            $auditMessage = "disabled succesfully";
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