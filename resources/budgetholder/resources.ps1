#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Resource-BudgetHolders
# PowerShell V2
#####################################################

# Set to true at start, because only when an error occurs it is set to false
$outputContext.Success = $true

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Set-AuthorizationHeaders {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Username,

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
    $authHeaders.Add('Accept', 'application/json; charset=utf-8')

    Write-Output $authHeaders
}

function Invoke-TopdeskRestMethod {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Method,

        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [object]
        $Body,

        [string]
        $ContentType = 'application/json; charset=utf-8',

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
                $splatParams['Body'] = [Text.Encoding]::UTF8.GetBytes($Body)
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        }
        catch {
            throw $_
        }
    }
}

function Get-TopdeskBudgetHolders {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $baseUrl,
        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$baseUrl/tas/api/budgetholders"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams
    Write-Information "Retrieved $($responseGet.count) budgetholders from Topdesk"
    Write-Output $responseGet
}

function New-TopdeskBudgetHolder {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/budgetholders"
        Method  = 'POST'
        Headers = $Headers
        body    = @{name = $Name } | ConvertTo-Json
    }
    $responseCreate = Invoke-TopdeskRestMethod @splatParams
    Write-Information "Created budgetholder with name [$($name)] and id [$($responseCreate.id)] in Topdesk"
    Write-Output $responseCreate
}
#endregion functions

#Begin
try {
    # Setup authentication headers    
    $splatParamsAuthorizationHeaders = @{
        UserName = $actionContext.Configuration.username
        ApiKey   = $actionContext.Configuration.apikey
    }
    $authHeaders = Set-AuthorizationHeaders @splatParamsAuthorizationHeaders
    
    # Get budget holders
    $splatParamsBudgetHolders = @{
        Headers = $authHeaders
        BaseUrl = $actionContext.Configuration.baseUrl
    }
    $TopdeskBudgetHolders = Get-TopdeskBudgetHolders @splatParamsBudgetHolders

    # Remove items with no name
    $TopdeskBudgetHolders = $TopdeskBudgetHolders.Where({ $_.Name -ne "" -and $_.Name -ne $null })
    $rRefSourceData = $resourceContext.SourceData.Where({ $_.Name -ne "" -and $_.Name -ne $null })

    # Process
    foreach ($HelloIdBudgetHolder in $rRefSourceData) {
        if (-not($TopdeskBudgetHolders.Name -eq $HelloIdBudgetHolder.name)) {
            if (-not ($actionContext.DryRun -eq $true)) {
                Write-Information "Creating Topdesk budgetholder with the name [$($HelloIdBudgetHolder.name)] in Topdesk."
                # Create budget holder
                $splatParamsCreateBudgetHolder = @{
                    Headers = $authHeaders
                    BaseUrl = $actionContext.Configuration.baseUrl
                    Name    = $HelloIdBudgetHolder.name
                }
                $newBudgetHolder = New-TopdeskBudgetHolder @splatParamsCreateBudgetHolder

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "CreateResource"    
                        Message = "Created Topdesk budgetholder with the name [$($newBudgetHolder.name)] and ID [$($newBudgetHolder.id)]"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "Preview: Would create Topdesk budgetholder $($HelloIdBudgetHolder.name)"
            }
        }
        else {
            Write-Information "Not creating budgetholder [$($HelloIdBudgetHolder.name)] as it already exists in Topdesk"
        }
    }
}
catch {
    $ex = $PSItem
    
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorMessage = "Could not create budgetholder [$($HelloIdBudgetHolder.name)]. Error:  $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }
    else {
        $errorMessage = "Could not create budgetholder [$($HelloIdBudgetHolder.name)]. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "CreateResource"    
            Message = $errorMessage
            IsError = $true
        })
}
finally {
    # Check if auditLogs contains errors, if errors are found, set success to false
    if ($outputContext.AuditLogs.IsError -contains $true) {
        $outputContext.Success = $false
    }
}