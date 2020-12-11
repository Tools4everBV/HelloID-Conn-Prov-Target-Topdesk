$config = $configuration | ConvertFrom-Json 
$path = $config.notifications.jsonPath

try {
    If (Test-Path $path) {
        $incidentList = Get-Content -Raw -Path $path | ConvertFrom-Json
        $incidents = $incidentList | Where-Object {$_.HelloIDAction -eq "Grant" } | Select-Object -Property displayName, identification
        write-output $incidents | ConvertTo-Json -Depth 10;
    }
}
catch{
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $errResponse = $reader.ReadToEnd();
        $auditMessage = "${errResponse}";
}