#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Entitlement-Grant
#
# Version: 2.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$pRef = $permissionReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region helperfunctions
function Get-VariablesFromString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $string
    )
    $regex = [regex]'\$\((.*?)\)'
    $variables = [System.Collections.Generic.list[object]]::new()

    $match = $regex.Match($string)
    while ($match.Success) {
        $variables.Add($match.Value)
        $match = $match.NextMatch()
    }
    Write-Output $variables
}

function Resolve-Variables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ref]
        $String,

        [Parameter(Mandatory)]
        $VariablesToResolve
    )
    foreach ($var in $VariablesToResolve | Select-Object -Unique) {
        ## Must be changed When changing the the way of lookup variables.
        $varTrimmed = $var.trim('$(').trim(')')
        $Properties = $varTrimmed.Split('.')

        $curObject = (Get-Variable ($Properties | Select-Object -First 1)  -ErrorAction SilentlyContinue).Value
        $Properties | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -ne $Properties[-1]) {
                $curObject = $curObject.$_
            } elseif ($null -ne $curObject.$_) {
                $String.Value = $String.Value.Replace($var, $curObject.$_)
            } else {
                Write-Verbose  "Variable [$var] not found"
                # $String.Value = $String.Value.Replace($var, $curObject.$_) # Add to override unresolved variables with null
            }
        }
    }
}

function Format-Description {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Description
    )
    try {
        $variablesFound = Get-VariablesFromString -String $Description
        Resolve-Variables -String ([ref]$Description) -VariablesToResolve $variablesFound

        Write-Output $Description
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
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
        $ContentType = 'application/json',

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

            if ($Body){
                Write-Verbose 'Adding body to request'
                $splatParams['Body'] = $Body
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

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
                Write-Verbose 'Adding body to request'
                $splatParams['Body'] = [Text.Encoding]::UTF8.GetBytes($Body)
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Get-TopdeskBranch {
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
        [ref]$Account,

        #[Parameter(Mandatory)]
        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )
    # Check if branch.lookupValue property exists in the account object set in the mapping
    if (-not($account.branch.Keys -Contains 'lookupValue')) {
        $errorMessage = "Requested to lookup branch, but branch.lookupValue is missing. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # When branch.lookupValue is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($Account.branch.lookupValue)) {

            # As branch is always a required field,  no branch in lookup value = error
            $errorMessage = "The lookup value for Branch is empty but it's a required field."
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
    } else {

        # Lookup Value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/branches"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-TopdeskRestMethod @splatParams
        $branch = $responseGet | Where-object name -eq $Account.branch.lookupValue

        # When branch is not found in Topdesk
        if ([string]::IsNullOrEmpty($branch.id)) {

            # As branch is a required field, if no branch is found, an error is logged
            $errorMessage = "Branch with name [$($Account.branch.lookupValue)] isn't found in Topdesk but it's a required field."
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        } else {

            # Branch is found in Topdesk, set in Topdesk
            $Account.branch.PSObject.Properties.Remove('lookupValue')
            $Account.branch | Add-Member -NotePropertyName id -NotePropertyValue $branch.id
        }
    }
}

function Get-TopdeskPersonById {
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
        [String]
        $PersonReference
    )

    # Lookup value is filled in, lookup person in Topdesk
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/persons/id/$PersonReference"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    # Output result if something was found. Result is empty when nothing is found (i think) - TODO: Test this!!!
    Write-Output $responseGet
}

function Get-TopdeskPerson {
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
        [String]
        $AccountReference,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if the account reference is empty, if so, generate audit message
    if ([string]::IsNullOrEmpty($AccountReference)) {

        # Throw an error when account reference is empty
        $errorMessage = "The account reference is empty. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # AcountReference is available, query person
    $splatParams = @{
        Headers                   = $Headers
        baseUrl                   = $baseUrl
        PersonReference           = $AccountReference
    }
    $person = Get-TopdeskPersonById @splatParams

    if ([string]::IsNullOrEmpty($person)) {
        $errorMessage = "Person with reference [$AccountReference)] is not found. If the person is deleted, you might need to regrant the entitlement."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    } else {
        Write-Output $person
    }
}

function Get-TopdeskPersonManager {
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

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if manager.id property exists in the account object set in the mapping
    if (-not($Account.manager.Keys -Contains 'id')) {
        $errorMessage = "Requested to lookup manager, but manager.id is missing. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Check if the manager reference is empty, if so, generate audit message or clear the manager attribute
    if ([string]::IsNullOrEmpty($Account.manager.id)) {

        # Check settings if it should clear the manager or generate an error
        if (-Not ([System.Convert]::ToBoolean($lookupErrorNoManagerReference))) {

            # True, no manager id = throw error
            $errorMessage = "The manager reference is empty and the connector is configured to stop when this happens."
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        } else {

            # False, as manager.Id is already empty, nothing needs to be done here
            Write-Verbose "Clearing manager. (lookupErrorNoManagerReference = False)"
        }
        return
    }

    # mRef is available, query manager
    $splatParams = @{
        Headers                   = $Headers
        baseUrl                   = $baseUrl
        PersonReference           = $managerReference
    }
    $personManager = Get-TopdeskPersonById @splatParams

    if ([string]::IsNullOrEmpty($personManager)) {
        $errorMessage = "Manager with reference [$($Account.manager.id)] is not found."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    } else {
        Write-Output $personManager
    }
}

function Set-TopdeskPersonArchiveStatus {
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
        [Ref]$TopdeskPerson,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Bool]
        $Archive
    )

    # Set ArchiveStatus variables based on archive parameter
    if ($Archive -eq $true) {
        $archiveStatus = 'personArchived'
        $archiveUri = 'archive'
    } else {
        $archiveStatus = 'person'
        $archiveUri = 'unarchive'
    }

    # Check the current status of the Person and compare it with the status in ArchiveStatus
    if ($archiveStatus -ne $TopdeskPerson.status) {

        # Archive / unarchive person
        Write-Verbose "[$archiveUri] person with id [$($TopdeskPerson.id)]"
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/person/$($TopdeskPerson.id)/$archiveUri"
            Method  = 'PATCH'
            Headers = $Headers
        }
        $null = Invoke-TopdeskRestMethod @splatParams
        $TopdeskPerson.status = $archiveStatus
    }
}

#Get-TopdeskIncidentCaller
    # same function for changes:
    #if emailaddress, lookup via "taslogonname??"
    # if employee -> use aRef
    # if manager -> use mRef
    #Get-TopdeskIncidentBranch
    #Get-TopdeskIncidentOperatorGroup
    #Get-TopdeskIncidentCategory
    #Get-TopdeskIncidentSubCategory
    #Get-TopdeskIncidentCallType
    #Get-TopdeskIncidentImpact
    #Format-TopdeskIncidentRequest

#endregion helperfunctions

#region Lookup
try {


#endregion Lookup
    $action = 'Process'

    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

    # Resolve branch id
    $splatParamsBranch = @{
        Account                   = [ref]$account
        AuditLogs                 = [ref]$auditLogs
        Headers                   = $authHeaders
        baseUrl                   = $config.baseUrl
    }
    Get-TopdeskBranch @splatParamsBranch

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
            Message = "Grant TOPdesk entitlement: [$($pRef.Reference)] to: [$($p.DisplayName)], will be executed during enforcement"
        })
    }

    if (-not($dryRun -eq $true)) {
        Write-Verbose "Granting TOPdesk entitlement: [$($pRef.Reference)] to: [$($p.DisplayName)]"

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "Grant TOPdesk entitlement: [$($pRef.Reference)] to: [$($p.DisplayName)] was successful."
            IsError = $false
        })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not grant TOPdesk entitlement: [$($pRef.Reference)] to: [$($p.DisplayName)]. Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not grant TOPdesk entitlement: [$($pRef.Reference)] to: [$($p.DisplayName)]. Error: $($ex.Exception.Message)"
    }
    Write-Verbose $errorMessage
    $auditLogs.Add([PSCustomObject]@{
        Message = $errorMessage
        IsError = $true
    })
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
