#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Resource-Branches
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

function Get-TopdeskCountry {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [string]
        $CountryName
    )


    # Lookup Value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/countries"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams
    $country = $responseGet | Where-object name -eq $CountryName

    # When country is not found in Topdesk
    if ([string]::IsNullOrEmpty($country.id)) {
        Write-Information "Available countries [$($responseGet | Convertto-json)]"
        $errorMessage = "Country [$CountryName)] not found in Topdesk. This is a mapping error."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
    }
    else {
        Write-Information "Retrieved country [$($country.name)] from TOPdesk [$($country.id)]"
        Write-Output $country
    }
}

function Get-TOPdeskBranches {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $baseUrl,
        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$baseUrl/tas/api/branches"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams
    Write-Information "Retrieved $($responseGet.count) branches from Topdesk"
    Write-Output $responseGet
}

function New-TOPdeskBranch {
    param (
        [ValidateNotNullOrEmpty()]
        [Object]
        $Branch,

        [ValidateNotNullOrEmpty()]
        [String]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/branches"
        Method  = 'POST'
        Headers = $Headers
        Body    = $Branch | ConvertTo-Json
    }
    $responseCreate = Invoke-TOPdeskRestMethod @splatParams
    Write-Information "Created branch with name [$($Branch.name)] and id [$($responseCreate.id)] in TOPdesk"
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
    
    # Get branches
    $splatParamsBranches = @{
        Headers = $authHeaders
        BaseUrl = $actionContext.Configuration.baseUrl
    }
    $TopdeskBranches = Get-TOPdeskBranches @splatParamsBranches

    # Remove items with no name
    $TopdeskBranches = $TopdeskBranches.Where({ $_.name -ne "" -and $_.name -ne $null })
    $rRefSourceData = $resourceContext.SourceData.Where({ $_.name -ne "" -and $_.name -ne $null })

    # Lookup country
    $splatParamsCountry = @{
        Headers     = $authHeaders
        BaseUrl     = $actionContext.Configuration.baseUrl
        CountryName = 'Nederland'
    }
    $country = Get-TopdeskCountry @splatParamsCountry

    if ($outputContext.AuditLogs.isError -contains $true) {
        throw "Error(s) occured while looking up required values"
    }

    # Process
    foreach ($HelloIdBranch in $rRefSourceData) {
        try {
            # Mapping how to create a branch. https://developers.topdesk.com/explorer/?page=supporting-files#/Branches/createBranch
            $branch = [PSCustomObject]@{
                name          = $HelloIdBranch.name
                postalAddress = @{
                    country = @{id = $country.id }
                }
                branchType    = 'independentBranch' # valid values: 'independentBranch' 'headBranch' 'hasAHeadBranch'.
            }
            if (-not($TopdeskBranches.name -eq $branch.name)) {
                if (-not ($actionContext.DryRun -eq $true)) {
                    Write-Information "Creating TOPdesk branch with the name [$($branch.name)] in TOPdesk..."
                    # Create branch
                    $splatParamsCreateBranch = @{
                        Headers = $authHeaders
                        BaseUrl = $actionContext.Configuration.baseUrl
                        Branch  = $branch
                    }
                    $newBranch = New-TOPdeskBranch @splatParamsCreateBranch

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = "CreateResource"    
                            Message = "Created Topdesk branch with the name [$($newBranch.name)] and ID [$($newBranch.id)]"
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "Preview: Would create Topdesk branch $($branch.name)"
                }
            }
            else {
                Write-Information "Not creating branch [$($branch.name)] as it already exists in Topdesk"
            }
        }
        catch {
            $ex = $PSItem

            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
                    $errorMessage = $($ex.ErrorDetails.Message)
                }
                else {
                    $errorMessage = $($ex.Exception.Message)
                }
                $auditMessage = "Could not create branch [$($branch.name)]. Error: $($errorMessage)"
                Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage)"
            }
            else {
                $auditMessage = "Could not create branch [$($branch.name)]. Error: $($ex.Exception.Message)"
                Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            }
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CreateResource"    
                    Message = $auditMessage
                    IsError = $true
                })
        }
    }
}
catch {
    $ex = $PSItem

    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            $errorMessage = $($ex.ErrorDetails.Message)
        }
        else {
            $errorMessage = $($ex.Exception.Message)
        }
        $auditMessage = "Could not create branches. Error: $($errorMessage)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($errorMessage)"
    }
    else {
        $auditMessage = "Could not create branches. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "CreateResource"    
            Message = $auditMessage
            IsError = $true
        })
}
finally {
    # Check if auditLogs contains errors, if errors are found, set success to false
    if ($outputContext.AuditLogs.IsError -contains $true) {
        $outputContext.Success = $false
    }
}