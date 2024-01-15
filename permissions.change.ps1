#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Permissions-Changes
#
# Version: 3.0.0 | new-powershell-connector
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

try {
    $permissionList = Get-Content -Raw -Encoding utf8 -Path $actionContext.Configuration.notificationJsonPath | ConvertFrom-Json
    $permissions = $permissionList | Select-Object -Property displayName, identification
    $outputContext.Permissions = $permissions
}
catch {
    $ex = $PSItem
    $errorMessage = "Could not retrieve TOPdesk permissions. Error: $($ex.Exception.Message)"
    Write-Warning $errorMessage
}