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
$mRef = $managerAccountReference | ConvertFrom-Json
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

function Get-HelloIdTopdeskTemplateById {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $JsonPath,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Id,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Type,            # 'grant' or 'revoke'

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if file exists.
    try {
        $permissionList = Get-Content -=JsonPath $config.notificationJsonPath
    } catch {
        $ex = $PSItem
        $errorMessage = "Could not retrieve Topdesk permissions file. Error: $($ex.Exception.Message)"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Check if entitlement with id exists
    $entitlementSet = $permissionList | Where-Object {($_.Identification.id -eq $pRef.id)}
    if ([string]::IsNullOrEmpty($entitlementSet)) {
        $errorMessage = "Could not find entitlement set with id '$($pRef.id)'. This is likely an issue with the json file."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Check if entitlement with id and specific type exists
    if (-not($entitlementSet.Keys -Contains $type)) {
        $errorMessage = "Could not find grant entitlement for entitlementSet '$($pRef.id)'. This is likely an issue with the json file."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # If empty, nothing should be done.
    if ([string]::IsNullOrEmpty($entitlementSet.$type)) {
        $message = "Action '$type' for entitlement '$($pRef.id)' is not configured."
        $auditLogs.Add([PSCustomObject]@{
            Message = $message
            IsError = $false
        })
        return
    }

    Write-Output $entitlementSet.$type
}


function Get-TopdeskTemplateById {
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
        $Id,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    $splatParams = @{
        Uri     = "$baseUrl/tas/api/applicableChangeTemplates"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    $topdeskTemplate = $responseGet.results | Where-Object { ($_.number -eq $TemplateId) }

    if ([string]::IsNullOrEmpty($topdeskTemplate)) {
        $errorMessage = "Topdesk template [$TemplateId] not found. Please verify this template exists and it's available for the API in Topdesk."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    Write-Output $topdeskTemplate
}

function Format-Description {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Description
    )

    $descriptionFormatted = Invoke-Expression "`"$Description`""
    Write-Output $descriptionFormatted
}

function Get-TopdeskRequesterByType {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Type,                        # 'email of requester' or 'employee' or 'manager'

        [string]
        $accountReference,            # optional, only required when type is employee

        [string]
        $managerAccountReference,     # optional, only required when type is manager

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Validate employee entry
    if ($type -eq 'employee') {
        if ([string]::IsNullOrEmpty($accountReference)) {
            $errorMessage = "Could not set requester: The account reference is empty."
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        } else {
            Write-Output $managerAccountReference
        }
        return
    }

    # Validate employee entry
    if ($type -eq 'manager') {
        if ([string]::IsNullOrEmpty($managerAccountReference)) {
            $errorMessage = "Could not set requester: The manager account reference is empty."
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        } else {
            Write-Output $managerAccountReference
        }
        return
    }

    # Query email address
    $splatParams = @{
        Uri     = "$baseUrl/tas/api//persons?email=$type"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams        #todo: have to find out what the response looks like

    #Validate static requester
    if ([string]::IsNullOrEmpty($responseGet)) {
        $errorMessage = "Could not set requester: Topdesk person with email [$Type] not found."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }
    Write-Output $responseGet.id
}



#endregion

try {
#possibly todo
    #Get-TopdeskChangeAction
    #Get-TopdeskChangeCategory
    #Get-TopdeskChangeSubCategory
    #Get-TopdeskChangeChangeType
    #Get-TopdeskChangeImpact
    #Get-TopdeskChangePriority

#region lookuptemplate

    # Lookup template from json file
    $splatParamsHelloIdTopdeskTemplate = @{
        Headers          = $Headers
        baseUrl          = $baseUrl
        Id               = $pRef.id
        AuditLogs        = $auditLogs
    }
    $template = Get-HelloIdTopdeskTemplateById @splatParamsHelloIdTopdeskTemplate

    # If template is not empty (both by design or due to an error), process to lookup the information in the template
    if ([string]::IsNullOrEmpty($template)) {
        Throw 'HelloID Template not found'
    }

    # Lookup Topdesk template id (sja xyz)
    $splatParamsTopdeskTemplate = @{
        Headers          = $Headers
        baseUrl          = $baseUrl
        Id               = $template.Template
        AuditLogs        = $auditLogs
    }
    $template = Get-TopdeskTemplateById @splatParamsTopdeskTemplate

    # Resolve variables in the BriefDescription field
    $splatParamsBriefDescription = @{
        description       = $template.BriefDescription
    }
    $briefDescription = Format-Description -@splatParamsBriefDescription

    # Resolve variables in the request field
    $splatParamsRequest = @{
        description       = $template.request
    }
    $request = Format-Description -@splatParamsRequest

    # Resolve requester
    $splatParamsTopdeskRequester = @{
        Headers          = $Headers
        baseUrl          = $baseUrl
        Type             = $template.requester
        AuditLogs        = $auditLogs
    }
    $requester = Get-TopdeskRequesterByType @splatParamsTopdeskRequester


    # Validate change type

    # Something with the person. If the person is archived, unarchive the person (employee/manager) rearchive afterwards









# alles is goed. Check of the berichten verzonden moeten worden (Dit moet wellicht --voor-- de lookup fase uitgevoerd worden.)
if ($config.notifications.disable -eq $true) {
    $dryRun = $true
    $success = $true
}
    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
            Message = "Grant Topdesk entitlement: [$($pRef.Reference)] to: [$($p.DisplayName)], will be executed during enforcement"
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
        $errorMessage = "Could not $action person. Error: $($ex.ErrorDetails.Message)"
    } else {
        $errorMessage = "Could not $action person. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }

    # Only log when there are no lookup values, as these generate their own audit message
    if ($ex.Exception.Message -eq 'HelloID Template not found') {
        $success = -not($auditLogs.isError -contains -$true)
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
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
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
