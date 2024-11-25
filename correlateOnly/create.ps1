#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Create
# Correlate to account
# PowerShell V2
#####################################################

# Set debug logging
switch ($($actionContext.Configuration.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

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

function Get-TopdeskPersonByCorrelationAttribute {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [Object]
        $CorrelationValue,

        [ValidateNotNullOrEmpty()]
        [String]
        $CorrelationField,

        [ValidateNotNullOrEmpty()]
        [String]
        $PersonType
    )

    # Lookup value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/persons?page_size=2&query=$($CorrelationField)=='$($CorrelationValue)'"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    # Check if only one result is returned
    if ([string]::IsNullOrEmpty($responseGet.id)) {
        # no results found
        Write-Output $null
    }
    elseif ($responseGet.Count -eq 1) {
        # one record found, correlate, return user
        write-output $responseGet
    }
    else {
        # Multiple records found, correlation
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Multiple [$($responseGet.Count)] $($PersonType)s found with [$CorrelationField] [$($CorrelationValue)]. Login names: [$($responseGet.tasLoginName -join ', ')]"
                IsError = $true
            })
    }
}
#endregion functions

#region correlation 
try {
    $action = 'Process'
    
    # Setup authentication headers
    $splatParamsAuthorizationHeaders = @{
        UserName = $actionContext.Configuration.username
        ApiKey   = $actionContext.Configuration.apikey
    }
    $authHeaders = Set-AuthorizationHeaders @splatParamsAuthorizationHeaders

    # Check if we should try to correlate the account
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

        if ([string]::IsNullOrEmpty($correlationField)) {
            Write-Warning "Correlation is enabled but not configured correctly."
            throw "Correlation is enabled but not configured correctly."
        }

        if ([string]::IsNullOrEmpty($correlationValue)) {
            Write-Warning "The correlation value for [$correlationField] is empty. This is likely a scripting issue."
            throw "The correlation value for [$correlationField] is empty. This is likely a scripting issue."
        }

        # get person
        $splatParamsPerson = @{
            correlationValue = $correlationValue
            correlationField = $correlationField
            Headers          = $authHeaders
            BaseUrl          = $actionContext.Configuration.baseUrl
            PersonType       = 'person'
        }
        $TopdeskPerson = Get-TopdeskPersonByCorrelationAttribute @splatParamsPerson
    }
    else {
        throw "Configuration of correlation is mandatory."
    }
    #endregion correlation

    #region Calulate action
    if (-Not([string]::IsNullOrEmpty($TopdeskPerson))) {
        $action = 'Correlate'
    }    
    else {
        $action = 'NotFound' 
    }

    Write-Verbose "Check if current account can be found. Result: $action"
    #endregion Calulate action

    switch ($action) {       
        'Correlate' {
            #region correlate
            Write-Information "Account with id [$($TopdeskPerson.id)] and dynamicName [($($TopdeskPerson.dynamicName))] successfully correlated on field [$($correlationField)] with value [$($correlationValue)]"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CorrelateAccount"
                    Message = "Account with id [$($TopdeskPerson.id)] and dynamicName [($($TopdeskPerson.dynamicName))] successfully correlated on field [$($correlationField)] with value [$($correlationValue)]"
                    IsError = $false
                })

            $outputContext.AccountReference = $TopdeskPerson.id
            $outputContext.AccountCorrelated = $true
            $outputContext.Data.id = $TopdeskPerson.id
            $outputContext.Data.employeeNumber = $TopdeskPerson.employeeNumber
            
            break
            #endregion correlate
        }

        'NotFound' {                
            Write-Information "Account with [$($correlationField)] value [$($correlationValue)] is not found"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Account with [$($correlationField)] value [$($correlationValue)] is not found"
                    IsError = $true
                })

            break
        }
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            $errorMessage = "Could not $action person. Error: $($ex.ErrorDetails.Message)"
        }
        else {
            $errorMessage = "Could not $action person. Error: $($ex.Exception.Message)"
        }
    }
    else {
        $errorMessage = "Could not $action person. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }

    # Only log when there are no lookup values, as these generate their own audit message
    if (-Not($ex.Exception.Message -eq 'Error(s) occured while looking up required values')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
    }
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if ($outputContext.AuditLogs.IsError -notContains $true) {
        $outputContext.Success = $true
    }

    # Check if accountreference is set, if not set, set this with default value as this must contain a value
    if ([String]::IsNullOrEmpty($outputContext.AccountReference) -and $actionContext.DryRun -eq $true) {
        $outputContext.AccountReference = "DryRun: Currently not available"
    }
}