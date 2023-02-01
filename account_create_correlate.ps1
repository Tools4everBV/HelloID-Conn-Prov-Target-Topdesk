#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Create-Correlate
#
# Version: 2.0
#####################################################

# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
#$mRef = $managerAccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Set debug logging
switch ($($config.IsDebug)) {
    $true  { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Account mapping. See for all possible options the Topdesk 'supporting files' API documentation at
# https://developers.topdesk.com/explorer/?page=supporting-files#/Persons/createPerson
$account = [PSCustomObject]@{
    employeeNumber      = $p.ExternalId

    # Optionally return data for use in other systems (only used in $result)
    networkLoginName    = $p.Accounts.MicrosoftActiveDirectory.UserPrincipalName
    tasLoginName        = $p.Accounts.MicrosoftActiveDirectory.UserPrincipalName
}
Write-Verbose ($account | ConvertTo-Json) # Debug output

#correlation attribute. Is used to lookup the user in the Get-TopdeskPerson function. Not migrated to settings because it's only used in the user create script.
$correlationAttribute = 'employeeNumber'

#endregion mapping

#region helperfunctions
function Set-AuthorizationHeaders {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Username,

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
                $splatParams['Body'] = [Text.Encoding]::UTF8.GetBytes($Body)
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Get-TopdeskPersonByCorrelationAttribute {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $Account,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CorrelationAttribute,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $PersonType,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if the correlation attribute exists in the account object set in the mapping
    if (-not([bool]$account.PSObject.Properties[$CorrelationAttribute])) {
        $errorMessage = "The correlation attribute [$CorrelationAttribute] is missing in the account mapping. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Check if the correlationAttribute is not empty
    if ([string]::IsNullOrEmpty($account.$CorrelationAttribute)) {
        $errorMessage = "The correlation attribute [$CorrelationAttribute] is empty. This is likely a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Lookup value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/persons?page_size=2&query=$($correlationAttribute)=='$($account.$CorrelationAttribute)'"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    # Check if only one result is returned
    if ([string]::IsNullOrEmpty($responseGet.id)) {
        # no results found
        $errorMessage = "No User found in Topdesk with [$CorrelationAttribute] [$($account.$CorrelationAttribute)] Login name: [$($responseGet.tasLoginName)]"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        Write-Output $null
    } elseif ($responseGet.Count -eq 1) {
        # one record found, correlate, return user
        

        write-output $responseGet
    } else {
        # Multiple records found, correlation
        $errorMessage = "Multiple [$($responseGet.Count)] $($PersonType)s found with [$CorrelationAttribute] [$($account.$CorrelationAttribute)]. Login names: [$($responseGet.tasLoginName -join ', ')]"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    }
}
#endregion helperfunctions

#region lookup
try {
    $action = 'Process'

    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

    # get person
    $splatParamsPerson = @{
        Account                   = $account
        AuditLogs                 = [ref]$auditLogs
        CorrelationAttribute      = $correlationAttribute
        Headers                   = $authHeaders
        BaseUrl                   = $config.baseUrl
        PersonType                = 'person'
    }
    $TopdeskPerson = Get-TopdeskPersonByCorrelationAttribute @splatParamsPerson

    # Write-Verbose ($TopdeskPerson | ConvertTo-Json) # Debug output

    if ($auditLogs.isError -contains -$true) {
        Throw "Error(s) occured while looking up required values"
    }
    

#endregion lookup

    if ($dryRun -eq $true) {
        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "$action Topdesk account for: [$($p.DisplayName)], will be corrolated during enforcement"
        })
    }

    # Process
    if (-not($dryRun -eq $true)){
        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "Account with id [$($TopdeskPerson.id)] successfully correlated"
            IsError = $false
        })
    }


} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        #write-verbose ($ex | ConvertTo-Json)

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            $errorMessage = "Could not $action person. Error: $($ex.ErrorDetails.Message)"
        } else {
            #$errorObj = Resolve-HTTPError -ErrorObject $ex
            $errorMessage = "Could not $action person. Error: $($ex.Exception.Message)"
        }
    } else {
        $errorMessage = "Could not $action person. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }

    # Only log when there are no lookup values, as these generate their own audit message
    if (-Not($ex.Exception.Message -eq 'Error(s) occured while looking up required values')) {
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    }
# End
} finally {
   $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $TopdeskPerson.id
        Auditlogs        = $auditLogs
        Account          = $account

        # Optionally return data for use in other systems
        ExportData = [PSCustomObject]@{
            Id                  = $TopdeskPerson.id
            employeeNumber      = $account.employeeNumber
        }
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
#endregion Write
