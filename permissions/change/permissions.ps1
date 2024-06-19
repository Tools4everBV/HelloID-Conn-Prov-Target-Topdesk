#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Permissions-Changes
# PowerShell V2
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

try {
    $permissionList = Get-Content -Raw -Encoding utf8 -Path $actionContext.Configuration.notificationJsonPath | ConvertFrom-Json
    foreach ($permission in $permissionList) {
        $outputContext.Permissions.Add(
            @{
                displayName    = $permission.DisplayName
                identification = @{
                    Id = $permission.Identification.id
                }
            }
        )
    }
}
catch {
    $ex = $PSItem
    $errorMessage = "Could not retrieve TOPdesk permissions. Error: $($ex.Exception.Message)"
    Write-Warning $errorMessage
}