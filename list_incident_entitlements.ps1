$path = 'C:\Temp\TOPdesk\exampleIncidents.json'

try {
    If (Test-Path $path) {
        $incidentList = Get-Content -Raw -Path $path | ConvertFrom-Json
        $permissions = $incidentList | Select-Object -Property displayName, identification
        write-output $permissions | ConvertTo-Json -Depth 10;
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