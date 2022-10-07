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
        $permissionList = Get-Content -Raw -Encoding utf8 -Path $config.notificationJsonPath | ConvertFrom-Json
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
    if (-not($entitlementSet.PSObject.Properties.Name -Contains $type)) {
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

    $topdeskTemplate = $responseGet.results | Where-Object { ($_.number -eq $Id) }

    if ([string]::IsNullOrEmpty($topdeskTemplate)) {
        $errorMessage = "Topdesk template [$Id] not found. Please verify this template exists and it's available for the API in Topdesk."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    Write-Output $topdeskTemplate.id
}

function Format-Description {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Description
    )

    $descriptionFormatted = $ExecutionContext.InvokeCommand.ExpandString($Description)
    Write-Output $descriptionFormatted
}

function Confirm-Description {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Description,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $AttributeName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $id,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $AllowedLength,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )
    if ($Description.Length -gt $AllowedLength) {
        $errorMessage = "Could not grant TOPdesk entitlement [$id]: The attribute [$AttributeName] exceeds the max amount of [$AllowedLength] characters. Please shorten the value for this attribute in the JSON file. Value: [$Description]"
        
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    } #else { 
        #Write-Verbose "The length for string [$Description] is [$($Description.Length)] which is shorter than the allowed length [$allowedLength]"
    #}
}

function Get-TopdeskRequesterByType {
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
        [string]
        $Type,                        # 'email of requester' or 'employee' or 'manager'

        [string]
        $accountReference,            # optional, only required when type is employee

        [string]
        $managerAccountReference,     # optional, only required when type is manager

        [string]
        $managerFallback,             # optional, will be used when the manager reference is empty

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Validate employee entry
    if ($type -eq 'employee') {
        if ([string]::IsNullOrEmpty($accountReference)) {
            $errorMessage = "Could not set requester: The account reference is empty." # add Could not grant TOPdesk entitlement: [$($pRef.id)]
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
        write-verbose "Type: Manager $([string]::IsNullOrEmpty($managerAccountReference))"
        if ([string]::IsNullOrEmpty($managerAccountReference)) {
            write-verbose "Type: Manager - managerAccountReference leeg"
            if ([string]::IsNullOrEmpty($managerFallback)) {
                write-verbose "Type: Manager - managerAccountReference - leeg - fallback leeg"
                $errorMessage = "Could not set requester: The manager account reference is empty and no fallback email is configured." # Could not grant TOPdesk entitlement: [$($pRef.id)]
                $auditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
                return
            } else {
                write-verbose "Type: Manager - managerAccountReference - leeg - fallback gevuld"
                # Set fallback adress and look it up below
                $type = $managerFallback
            }
        } else {
            write-verbose "Type: Manager - managerAccountReference - gevuld: [$managerAccountReference]"
            Write-Output $managerAccountReference
            return
        }
    }

    # Query email address (manager fallback or static)
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/persons?email=$type"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams        #todo: have to find out what the response looks like

    # Check if only one result is returned
    if ([string]::IsNullOrEmpty($responseGet.id)) {

        # no results found
         $errorMessage = "Could not set requester: Topdesk person with email [$Type] not found."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    } elseif ($responseGet.Count -eq 1) {

        # one record found, correlate, return id
        write-output $responseGet.id
    } else {

        # Multiple records found, correlation
        $errorMessage = "Multiple [$($responseGet.Count)] persons found with Email address [$Email]. Login names: [$($responseGet.tasLoginName)]"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    }
}

function Get-TopdeskChangeType {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $changeType,                        # 'simple' or 'extensive'

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Show audit message if type is empty
    if ([string]::IsNullOrEmpty($changeType)) {
        $errorMessage = "The change type is not set. It should be set to 'simple' or 'extensive'"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Show audit message if type is not 
    if (-not ($changeType -eq 'simple' -or $changeType -eq 'extensive')) {
        $errorMessage = "The configured change type [$changeType] is invalid. It should be set to 'simple' or 'extensive'"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    return $ChangeType.ToLower()
}


function New-TopdeskChange {
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
        [PsObject]
        $TopdeskChange,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/operatorChanges"
        Method  = 'POST'
        Headers = $Headers
        Body    = $TopdeskChange | ConvertTo-Json
    }
    Write-Verbose ($TopdeskChange | ConvertTo-Json)
    $change = Invoke-TopdeskRestMethod @splatParams

    Write-Verbose "Created change with number [$($change.number)]"

    Write-Output $change
}
#endregion

try {

#region lookuptemplate
    if ($config.disableNotifications -eq 'true') {
        Throw "Notifications are disabled"
    }
    $action = 'Process'

    # Lookup template from json file (C00X)
    $splatParamsHelloIdTopdeskTemplate = @{
        JsonPath        = $config.notificationJsonPath
        Id              = $pRef.id
        Type            = "Grant"
        AuditLogs       = [Ref]$auditLogs
    }
    $template = Get-HelloIdTopdeskTemplateById @splatParamsHelloIdTopdeskTemplate
    
    # If template is not empty (both by design or due to an error), process to lookup the information in the template
    if ([string]::IsNullOrEmpty($template)) {
        Throw 'HelloID template not found'
    }

    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

    # Lookup Topdesk template id (sja xyz)
    $splatParamsTopdeskTemplate = @{
        Headers          = $authHeaders
        BaseUrl          = $config.baseUrl
        Id               = $template.Template
        AuditLogs        = [Ref]$auditLogs
    }
    $templateId = Get-TopdeskTemplateById @splatParamsTopdeskTemplate

    # Add value to  request object
    $requestObject += @{
        template = @{
            id = $templateId
        }
    }

    # Resolve variables in the BriefDescription field
    $splatParamsBriefDescription = @{
        description       = $template.BriefDescription
    }
    $briefDescription = Format-Description @splatParamsBriefDescription

    #Validate length of briefDescription
    $splatParamsValidateBriefDescription = @{
        Description      = $briefDescription
        AllowedLength    = 80
        AttributeName    = 'BriefDescription'
        AuditLogs        = [Ref]$auditLogs
        id               = $pref.id
    }
    Confirm-Description @splatParamsValidateBriefDescription

    # Add value to request object
    $requestObject += @{
        briefDescription = $briefDescription
    }

    # Resolve variables in the request field
    $splatParamsRequest = @{
        description       = $template.Request
    }
    $request = Format-Description @splatParamsRequest

    # Add value to request object
    $requestObject += @{
        request = $request
    }

    # Resolve requester
    $splatParamsTopdeskRequester = @{
        Headers                 = $authHeaders
        baseUrl                 = $config.baseUrl
        Type                    = $template.Requester
        accountReference        = $aRef
        managerAccountReference = $mRef
        managerFallback         = $config.notificationRequesterFallback
        AuditLogs               = [Ref]$auditLogs
    }
    $requesterId = Get-TopdeskRequesterByType @splatParamsTopdeskRequester

    # Add value to request object
    $requestObject += @{
        requester = @{
            id = $requesterId
        }
    }

    # Validate change type
    $splatParamsTopdeskTemplate = @{
        changeType       = $template.ChangeType
        AuditLogs        = [Ref]$auditLogs
    }
    $changeType = Get-TopdeskChangeType @splatParamsTopdeskTemplate

    # Add value to request object
    $requestObject += @{
        changeType = $changeType
    }

    ## Support for optional parameters, are only added when they exist and are not set to null
    # Action
    if (-not [string]::IsNullOrEmpty($template.Action)) {
        $requestObject += @{
            action = $template.Action
        }
    }

    # Category
    if (-not [string]::IsNullOrEmpty($template.Category)) {
        $requestObject += @{
            category = $template.Category
        }
    }

    # SubCategory
    if (-not [string]::IsNullOrEmpty($template.SubCategory)) {
        $requestObject += @{
            subCategory = $template.SubCategory
        }
    }

    # ExternalNumber
    if (-not [string]::IsNullOrEmpty($template.ExternalNumber)) {
        $requestObject += @{
            externalNumber = $template.ExternalNumber
        }
    }

    # Impact
    if (-not [string]::IsNullOrEmpty($template.Impact)) {
        $requestObject += @{
            impact = $template.Impact
        }
    }

    # Benefit
    if (-not [string]::IsNullOrEmpty($template.Benefit)) {
        $requestObject += @{
            benefit = $template.Benefit
        }
    }

    # Priority
    if (-not [string]::IsNullOrEmpty($template.Priority)) {
        $requestObject += @{
            priority = $template.Priority
        }
    }
    
    if ($auditLogs.isError -contains $true) {
        Throw "Error(s) occured while looking up required values"
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {

        $auditLogs.Add([PSCustomObject]@{
            Message = "Grant Topdesk entitlement: [$($pRef.id)] to: [$($p.DisplayName)], will be executed during enforcement"
        })
        Write-Verbose ($requestObject | ConvertTo-Json)
    }

    if (-not($dryRun -eq $true)) {
        Write-Verbose "Granting TOPdesk entitlement: [$($pRef.id)] to: [$($p.DisplayName)]"

        # Create change in Topdesk
        $splatParamsTopdeskChange = @{
            Headers                 = $authHeaders
            baseUrl                 = $config.baseUrl
            TopdeskChange           = $requestObject
            AuditLogs               = [Ref]$auditLogs
        }
        $TopdeskChange = New-TopdeskChange @splatParamsTopdeskChange

    # Todo: stuff to requester (have to test if this is required)
    # Something with the person. If the person is archived, unarchive the person (employee/manager) rearchive afterwards
    # # Prepare manager record, if manager has to be set
    # if (-Not([string]::IsNullOrEmpty($account.manager.id))) {
    #     if ($TopdeskManager.isManager -eq $false) {
    #         if ($TopdeskManager.status -eq 'personArchived') {

    #             # Unarchive person
    #             $shouldArchive  = $true
    #             $splatParamsManagerUnarchive = @{
    #                 TopdeskPerson   = [ref]$TopdeskManager
    #                 Headers         = $authHeaders
    #                 BaseUrl         = $config.baseUrl
    #                 Archive         = $false
    #             }
    #             Set-TopdeskPersonArchiveStatus @splatParamsManagerUnarchive
    #         }

    #         # Set isManager to true
    #         $splatParamsManagerIsManager = @{
    #             TopdeskPerson   = [ref]$TopdeskManager
    #             Headers         = $authHeaders
    #             BaseUrl         = $config.baseUrl
    #             IsManager       = $true
    #         }
    #         Set-TopdeskPersonIsManager @splatParamsManagerIsManager

    #         # Archive manager if required
    #         if ($shouldArchive -and $TopdeskManager.status -ne 'personArchived') {

    #             # Archive manager
    #             $splatParamsManagerArchive = @{
    #                 TopdeskPerson   = [ref]$TopdeskManager
    #                 Headers         = $authHeaders
    #                 BaseUrl         = $config.baseUrl
    #                 Archive         = $true
    #             }
    #             Set-TopdeskPersonArchiveStatus @splatParamsManagerArchive
    #         }
    #     }
    # }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "Grant TOPdesk entitlement: [$($pRef.id)] with number [$($TopdeskChange.number)] was successful."
            IsError = $false
        })
    }
} catch {
    $success = $false
    $ex = $PSItem
    
    switch ($ex.Exception.Message) {

        'HelloID Template not found' {
                # Only log when there are no lookup values, as these generate their own audit message, set success based on error state
                $success = -Not($auditLogs.isError -contains $true)
        }

        'Error(s) occured while looking up required values' {
            # Only log when there are no lookup values, as these generate their own audit message
        }

        'Notifications are disabled' {
            # Don't do anything when notifications are disabled, mark them as a success
            $success = $true
            $message = 'Not creating Topdesk change, because the notifications are disabled in the connector configuration.'
            $auditLogs.Add([PSCustomObject]@{
                Message = $message
                IsError = $false
            })

        } default {
            Write-Verbose ($ex | ConvertTo-Json) # Debug - Test
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorMessage ="Could not grant TOPdesk entitlement: [$($pRef.id)]. Error: $($ex.ErrorDetails.Message)"
            } else {
                $errorMessage = "Could not grant TOPdesk entitlement: [$($pRef.id)]. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
            } 
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        }
    }
# End
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
