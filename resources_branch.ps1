#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Resource-Branches
#
# Version: 3.0.0 | Powershell V2
#####################################################

# Set to true at start, because only when an error occurs it is set to false
$outputContext.Success = $true

# Set debug logging
switch ($($actionContext.Configuration.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-HTTPError {
    param (
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
    $authHeaders.Add("Accept", 'application/json')

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
            Throw $_
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
        write-verbose "Aviable countries [$($responseGet | Convertto-json)]"
        $errorMessage = "Country [$CountryName)] not found in Topdesk. This is a mapping error."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
    }
    else {
        Write-Verbose "Retrieved country [$($country.name)] from TOPdesk [$($country.id)]"
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
    Write-Verbose "Retrieved $($responseGet.count) branches from Topdesk"
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
    Write-Verbose "Created branch with name [$($Branch.name)] and id [$($responseCreate.id)] in TOPdesk"
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
        Throw "Error(s) occured while looking up required values"
    }

    # Process
    foreach ($HelloIdBranch in $rRefSourceData) {
        
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
                try {
                    Write-Verbose "Creating TOPdesk branch with the name [ $($branch.name) ] in TOPdesk..."
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
                catch {
                    $ex = $PSItem
                    
                    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                        $errorMessage = "Could not create branch [$($branch.name)]. Error: $($ex.ErrorDetails.Message)"
                    }
                    else {
                        $errorMessage = "Could not create branch [$($branch.name)]. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
                    }
                    Write-Verbose "$errorMessage"
                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Action  = "CreateResource"    
                            Message = $errorMessage
                            IsError = $true
                        })
                }
            }
            else {
                Write-Warning "Preview: Would create Topdesk branch $($branch.name)"
            }
        }
        else {
            Write-Verbose "Not creating branch [$($branch.name)] as it already exists in Topdesk"
        }
    }
}
catch {
    $ex = $PSItem
    
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not create branch. Error:  $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }
    else {
        $errorMessage = "Could not create branch. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }

    # Only log when there are no lookup values, as these generate their own audit message
    if (-Not($ex.Exception.Message -eq 'Error(s) occured while looking up required values')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateResource"    
                Message = $errorMessage
                IsError = $true
            })
    }
}
finally {
    # Check if auditLogs contains errors, if errors are found, set success to false
    if ($outputContext.AuditLogs.IsError -contains $true) {
        $outputContext.Success = $false
    }
}