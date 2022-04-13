#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Permissions-Changes
#
# Version: 2.0
#####################################################

# Initialize default values
$config = $configuration | ConvertFrom-Json

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Enable debug verbose logging
$VerbosePreference = 'Continue'

try {
    $permissionList = Get-Content -Raw -Path $config.notificationJsonPath | ConvertFrom-Json
    $permissions = $permissionList | Select-Object -Property displayName, identification
    write-output $permissions | ConvertTo-Json -Depth 10
} catch {
    $ex = $PSItem
    $errorMessage = "Could not retrieve Topdesk permissions. Error: $($ex.Exception.Message)"
    Write-Verbose $errorMessage
}