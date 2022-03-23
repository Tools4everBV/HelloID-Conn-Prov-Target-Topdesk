#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Resource-BudgetHolders
# Usually mapped to Cost Centers
# Version: 1.0.0
#####################################################

# Initialize default values
$config = $configuration | ConvertFrom-Json
$rRef = $resourceContext | ConvertFrom-Json

$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Set-AuthorizationHeaders {
    [CmdletBinding()]
    param ()
    process {
        # Create basic authentication string
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("$($config.connection.userName):$($config.connection.apiKey)")
        $base64 = [System.Convert]::ToBase64String($bytes)

        # Set authentication headers
        $authHeaders = New-Object "System.Collections.Generic.Dictionary[[String], [String]]"
        $authHeaders.Add("Authorization", "BASIC $base64")
        $authHeaders.Add("Accept", 'application/json')
        Write-Output $authHeaders
    }
}

function Invoke-TOPdeskRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json; charset=utf-8',

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers
    )
    process {
        try {
            $splatParams = @{
                Uri         = $Uri
                Headers     = $Headers
                Method      = $Method
                ContentType = $ContentType
            }
            if ($Body) {
                Write-Verbose 'Adding body to request'
                $splatParams['Body'] = [Text.Encoding]::UTF8.GetBytes($Body)
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Get-TOPdeskBudgetHolders {
    [CmdletBinding()]
    param ()
    $splatGoupParams = @{
        Uri     = "$($config.connection.baseUrl)/tas/api/budgetholders"
        Method  = 'GET'
        Headers = Set-AuthorizationHeaders
    }
    $responseGetGroup = Invoke-TOPdeskRestMethod @splatGoupParams
    Write-Verbose "Retrieved $($responseGetGroup.count) budgetholders from TOPdesk"
    return $responseGetGroup
}

function New-TOPdeskBudgetHolder {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
    )

    $splatParams = @{
        Uri     = "$($config.connection.baseUrl)/tas/api/budgetholders"
        Method  = 'POST'
        Headers = Set-AuthorizationHeaders
        body    = @{name=$Name} | ConvertTo-Json
    }
    $responseCreate = Invoke-TOPdeskRestMethod @splatParams
    Write-Verbose "Created budgetholder with name [$($name)] and id [$($responseCreate.id)] in TOPdesk"
    return $responseCreate
}
#endregion

#Begin
try {
    $TopdeskBudgetHolders= Get-TOPdeskBudgetHolders

    # Remove items with no name
    [Void]$TopdeskBudgetHolders.Where({ $_.Name-ne "" })
    [Void]$rRef.sourceData.Where({ $_.Name -ne "" })

    # Process
    $success = $true
    foreach ($HelloIdBudgetHolder in $rRef.sourceData) {
        if (-not($TopdeskBudgetHolders -contains $HelloIdBudgetHolder.Name)) {
            # Create budgetholder
            if (-not ($dryRun -eq $true)) {
                try {
                    Write-Verbose "Creating TOPdesk budgetholder with the name [$($HelloIdBudgetHolder.Name)] in TOPdesk..."
                    $newBudgetHolder= New-TOPdeskBudgetHolder -Name $HelloIdBudgetHolder.Name
                    $auditLogs.Add([PSCustomObject]@{
                        Message = "Created TOPdesk budgetholder with the name [$($newBudgetHolder.Name)] and ID [$($newBudgetHolder.id)]"
                        IsError = $false
                    })
                } catch {
                    $success = $false
                    $ex = $PSItem
                    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                        $errorMessage = "Could not create budgetholder. Error: $($ex.ErrorDetails.Message)"
                    } else {
                        $errorMessage = "Could not create budgetholder. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
                    }
                    Write-Verbose "$errorMessage"
                    $auditLogs.Add([PSCustomObject]@{
                        Message = $errorMessage
                        IsError = $true
                    })
                }
            } else {
                Write-Verbose "Preview: Would create topdesk budgetholder $($HelloIdBudgetHolder.Name)"
            }
        } else {
            Write-Verbose "Not creating budgetholder [$($HelloIdBudgetHolder.Name)] as it already exists in TOPdesk"
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorMessage = "Could not create budgetholders. Error: $($ex.ErrorDetails.Message)"
    } else {
        $errorMessage = "Could not create budgetholders. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }
    $auditLogs.Add([PSCustomObject]@{
        Message = $errorMessage
        IsError = $true
    })
# End
} finally {
   $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}