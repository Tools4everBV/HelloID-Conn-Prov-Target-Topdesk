#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Resource-Departments
#
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
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $UserName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ApiKey
    )
    # Create basic authentication string
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("$UserName):$ApiKey)")
    $base64 = [System.Convert]::ToBase64String($bytes)

    # Set authentication headers
    $authHeaders = [System.Collections.Generic.Dictionary[string, string]]::new()
    $authHeaders.Add("Authorization", "BASIC $base64")
    $authHeaders.Add("Accept", 'application/json')
    Write-Output $authHeaders
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

function Get-TOPdeskDepartments {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $baseUrl,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers
    )

    $splatGoupParams = @{
        Uri     = "$baseUrl/tas/api/departments"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TOPdeskRestMethod @splatGoupParams
    Write-Verbose "Retrieved $($responseGet.count) departments from TOPdesk"
    Write-Output $responseGet
    }

function New-TOPdeskDepartment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $baseUrl,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$baseUrl/tas/api/departments"
        Method  = 'POST'
        Headers = $Headers
        body    = @{name=$Name} | ConvertTo-Json
    }
    $responseCreate = Invoke-TOPdeskRestMethod @splatParams
    Write-Verbose "Created department with name [$($name)] and id [$($responseCreate.id)] in TOPdesk"
    Write-Output $responseCreate
}
#endregion

#Begin
try {
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.connection.userName -ApiKey $Config.connection.apiKey
    $TopdeskDepartments = Get-TOPdeskDepartments -Headers $Config.connection.authHeaders -baseUrl $Config.connection.baseUrl

    # Remove items with no name
    [Void]$TopdeskDepartments.Where({ $_.Name-ne "" })
    [Void]$rRef.sourceData.Where({ $_.DisplayName -ne "" })

    # Process
    $success = $true
    foreach ($HelloIdDepartment in $rRef.sourceData) {
        if (-not($TopdeskDepartments.Name -contains $HelloIdDepartment.displayName)) {
            # Create department
            if (-not ($dryRun -eq $true)) {
                try {
                    Write-Verbose "Creating TOPdesk department with the name [$($HelloIdDepartment.displayName)] in TOPdesk..."
                    $newDepartment = New-TOPdeskDepartment -Name $HelloIdDepartment.displayName -baseUrl $Config.connection.baseUrl -Headers $authHeaders
                    $auditLogs.Add([PSCustomObject]@{
                        Message = "Created TOPdesk department with the name [$($newDepartment.name)] and ID [$($newDepartment.id)]"
                        IsError = $false
                    })
                } catch {
                    $success = $false
                    $ex = $PSItem
                    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                        $errorMessage = "Could not create department. Error: $($ex.ErrorDetails.Message)"
                    } else {
                        $errorMessage = "Could not create department. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
                    }
                    Write-Verbose "$errorMessage"
                    $auditLogs.Add([PSCustomObject]@{
                        Message = $errorMessage
                        IsError = $true
                    })
                }
            } else {
                Write-Verbose "Preview: Would create topdesk department $($HelloIdDepartment.displayName)"
            }
        } else {
            Write-Verbose "Not creating department [$($HelloIdDepartment.displayName)] as it already exists in TOPdesk"
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorMessage = "Could not create departments. Error: $($ex.ErrorDetails.Message)"
    } else {
        $errorMessage = "Could not create departments. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
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