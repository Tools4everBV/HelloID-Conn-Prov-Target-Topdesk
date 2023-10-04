#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Resource-BudgetHolders
#
# Version: 2.0.1
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
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("${Username}:${Apikey}")
    $base64 = [System.Convert]::ToBase64String($bytes)

    # Set authentication headers
    $authHeaders = [System.Collections.Generic.Dictionary[string, string]]::new()
    $authHeaders.Add("Authorization", "BASIC $base64")
    $authHeaders.Add("Accept", 'application/json')
    Write-Output $authHeaders
}

function Invoke-TopdeskRestMethod {
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
            throw $_
        }
    }
}

function Get-TopdeskBudgetHolders {
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

    $splatParams = @{
        Uri     = "$baseUrl/tas/api/budgetholders"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams
    Write-Verbose "Retrieved $($responseGet.count) budgetholders from Topdesk"
    Write-Output $responseGet
}

function New-TopdeskBudgetHolder {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/budgetholders"
        Method  = 'POST'
        Headers = $Headers
        body    = @{name=$Name} | ConvertTo-Json
    }
    $responseCreate = Invoke-TopdeskRestMethod @splatParams
    Write-Verbose "Created budgetholder with name [$($name)] and id [$($responseCreate.id)] in Topdesk"
    Write-Output $responseCreate
}


function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
        [object]$ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
}
#endregion

#Begin
try {
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apikey
    $TopdeskBudgetHolders = Get-TopdeskBudgetHolders -Headers $authHeaders -BaseUrl $Config.baseUrl

    # Remove items with no name
    $TopdeskBudgetHolders = $TopdeskBudgetHolders.Where({ $_.Name -ne "" -and  $_.Name -ne $null })
    $rRefSourceData = $rRef.sourceData.Where({ $_.Name -ne "" -and  $_.Name -ne $null })

    # Process
    $success = $true
    foreach ($HelloIdBudgetHolder in $rRefSourceData) {
        if (-not($TopdeskBudgetHolders.Name -eq $HelloIdBudgetHolder.name)) {
            # Create budgetholder
            if (-not ($dryRun -eq $true)) {
                try {
                    Write-Verbose "Creating Topdesk budgetholder with the name [$($HelloIdBudgetHolder.name)] in Topdesk..."
                    $newBudgetHolder = New-TopdeskBudgetHolder -Name $HelloIdBudgetHolder.name -BaseUrl $Config.baseUrl -Headers $authHeaders
                    $auditLogs.Add([PSCustomObject]@{
                        Message = "Created Topdesk budgetholder with the name [$($newBudgetHolder.name)] and ID [$($newBudgetHolder.id)]"
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
                Write-Verbose "Preview: Would create Topdesk budgetholder $($HelloIdBudgetHolder.name)"
            }
        } else {
            Write-Verbose "Not creating budgetholder [$($HelloIdBudgetHolder.name)] as it already exists in Topdesk"
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not create budgetholders. Error:  $($ex.Exception.Message) $($ex.ScriptStackTrace)"
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
