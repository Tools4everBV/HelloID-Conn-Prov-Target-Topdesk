$config = $configuration | ConvertFrom-Json
$path = $config.notifications.jsonPath

try {
    if (Test-Path $path) {
        $changeList = Get-Content -Raw -Path $path | ConvertFrom-Json

        $changes = $changeList | Select-Object -Property displayName, identification
        write-output $changes | ConvertTo-Json -Depth 10
    }

}
catch{
        $result = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($result)
        $reader.BaseStream.Position = 0
        $reader.DiscardBufferedData()
        $errResponse = $reader.ReadToEnd()
        $auditMessage = "${errResponse}  $_"
        Write-Verbose -Verbose -Message $auditMessage
}