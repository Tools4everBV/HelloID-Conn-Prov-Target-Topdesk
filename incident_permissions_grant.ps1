#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Entitlement-Grant-Incident
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
                $String.Value = $String.Value.Replace($var, $curObject.$_) # Add to override unresolved variables with null
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
        if ([string]::IsNullOrEmpty($aRef)) {
            $errorMessage = "Could not set requester: The account reference is empty."
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        } else {
            write-verbose "Type: Employee - accountReference - gevuld: [$aRef]"
            Write-Output $aRef
        }
        return
    }

    # Validate employee entry
    if ($type -eq 'manager') {
        write-verbose "Type: Manager $([string]::IsNullOrEmpty($mRef))"
        if ([string]::IsNullOrEmpty($mRef)) {
            write-verbose "Type: Manager - managerAccountReference leeg"
            if ([string]::IsNullOrEmpty($managerFallback)) {
                write-verbose "Type: Manager - managerAccountReference - leeg - fallback leeg"
                $errorMessage = "Could not set requester: The manager account reference is empty and no fallback email is configured."
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
            write-verbose "Type: Manager - managerAccountReference - gevuld: [$mRef]"
            Write-Output $mRef
            return
        }
    }

    # Query email address (manager fallback or static)
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/persons?email=$type"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

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
function New-TopdeskIncident {
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
        $TopdeskIncident,
        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )
    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/incidents"
        Method  = 'POST'
        Headers = $Headers
        Body    = $TopdeskIncident | ConvertTo-Json
    }
    Write-Verbose ($TopdeskIncident | ConvertTo-Json)
    $incident = Invoke-TopdeskRestMethod @splatParams
    Write-Verbose "Created incident with number [$($incident.number)]"
    Write-Output $incident
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
        $permissionList = Get-Content -Raw -Encoding utf8 -Path $JsonPath | ConvertFrom-Json
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
    $entitlementSet = $permissionList | Where-Object {($_.Identification.id -eq $id)}
    if ([string]::IsNullOrEmpty($entitlementSet)) {
        $errorMessage = "Could not find entitlement set with id '$($id)'. This is likely an issue with the json file."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Check if entitlement with id and specific type exists
    if (-not($entitlementSet.PSObject.Properties.Name -Contains $type)) {
        $errorMessage = "Could not find grant entitlement for entitlementSet '$($id)'. This is likely an issue with the json file."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # If empty, nothing should be done.
    if ([string]::IsNullOrEmpty($entitlementSet.$type)) {
        $message = "Action '$type' for entitlement '$($id)' is not configured."
        $auditLogs.Add([PSCustomObject]@{
            Message = $message
            IsError = $false
        })
        return
    }
    Write-Output $entitlementSet.$type
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
        $errorMessage = "Could not grant Topdesk entitlement [$id]: The attribute [$AttributeName] exceeds the max amount of [$AllowedLength] characters. Please shorten the value for this attribute in the JSON file. Value: [$Description]"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
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
        Uri     = "$BaseUrl/tas/api/persons/id/$PersonReference"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    # Output result if something was found. Result is empty when nothing is found
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
        $AuditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # AcountReference is available, query person
    $splatParams = @{
        Headers                   = $Headers
        BaseUrl                   = $BaseUrl
        PersonReference           = $AccountReference
    }
    $person = Get-TopdeskPersonById @splatParams

    if ([string]::IsNullOrEmpty($person)) {
        $errorMessage = "Person with reference [$AccountReference)] is not found. If the person is deleted, you might need to regrant the entitlement."
        $AuditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    } else {
        Write-Output $person
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
        $Archive,

        [Parameter()]
        [String]
        $ArchivingReason,

        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Set ArchiveStatus variables based on archive parameter
    if ($Archive -eq $true) {

         #When the 'archiving reason' setting is not configured in the target connector configuration
        if ([string]::IsNullOrEmpty($ArchivingReason)) {
            $errorMessage = "Configuration setting 'Archiving Reason' is empty. This is a configuration error."
            $AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
            Throw "Error(s) occured while looking up required values"
        }

        $splatParams = @{
            Uri     = "$baseUrl/tas/api/archiving-reasons"
            Method  = 'GET'
            Headers = $Headers
        }

        $responseGet = Invoke-TopdeskRestMethod @splatParams
        $archivingReasonObject = $responseGet | Where-object name -eq $ArchivingReason

        #When the configured archiving reason is not found in Topdesk
        if ([string]::IsNullOrEmpty($archivingReasonObject.id)) {
            $errorMessage = "Archiving reason [$ArchivingReason] not found in Topdesk"
            $AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
            Throw "Error(s) occured while looking up required values"
        } # else

        $archiveStatus = 'personArchived'
        $archiveUri = 'archive'
        $body = @{ id = $archivingReasonObject.id }
    } else {
        $archiveStatus = 'person'
        $archiveUri = 'unarchive'
        $body = $null
    }

    # Check the current status of the Person and compare it with the status in archiveStatus
    if ($archiveStatus -ne $TopdeskPerson.status) {

        # Archive / unarchive person
        Write-Verbose "[$archiveUri] person with id [$($TopdeskPerson.id)]"
        $splatParams = @{
            Uri     = "$BaseUrl/tas/api/persons/id/$($TopdeskPerson.id)/$archiveUri"
            Method  = 'PATCH'
            Headers = $Headers
            Body    = $body | ConvertTo-Json
        }
        $null = Invoke-TopdeskRestMethod @splatParams
        $TopdeskPerson.status = $archiveStatus
    }
}

function Get-TopdeskIdentifier {
    [CmdletBinding()]
    param (
        [Parameter()]
        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs,
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
        $Class,    
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $Value,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $Endpoint,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $SearchAttribute
    )

    # Check if property exists in the template object set in the mapping
    if (-not($Template.PSobject.Properties.Name -Contains $Class)) {
        $errorMessage = "Requested to lookup [$Class], but the [$Value] parameter is missing in the template file"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }
    
    Write-Verbose "Class [$class]: Variable [$`Value] has value [$($Value)] and endpoint [$($Endpoint)?query=$($SearchAttribute)==$($Value))]"

    # Lookup Value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = $baseUrl + $Endpoint + "?query=" + $SearchAttribute + "==" + $Value
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    $result = $responseGet | Where-object $SearchAttribute -eq $Value

    # When attribute $Class with $Value is not found in Topdesk
    if ([string]::IsNullOrEmpty($result.id)) {
        $errorMessage = "Class [$Class] with SearchAttribute [$SearchAttribute] with value [$Value] isn't found in Topdesk"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        }) 
    } else {
        # $id is found in Topdesk, set in Topdesk
        Write-Output $result.id
    }
}
#endregion

try {
    if ($config.disableNotifications -eq 'true') {
        Throw "Notifications are disabled"
    }

    $requestObject = @{}
    # Lookup template from json file (I00X)
    $splatParamsHelloIdTopdeskTemplate = @{
        JsonPath        = $config.notificationJsonPath
        Id              = $pRef.id
        Type            = "Grant"
        AuditLogs       = [Ref]$auditLogs
    }
    $template = Get-HelloIdTopdeskTemplateById @splatParamsHelloIdTopdeskTemplate

    # If template is not empty (both by design or due to an error), process to lookup the information in the template
    if ([string]::IsNullOrEmpty($template)) {
        Throw "HelloID template not found"
    }

    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

    # Resolve caller
    $splatParamsTopdeskCaller = @{
        Headers                 = $authHeaders
        baseUrl                 = $config.baseUrl
        Type                    = $template.Caller
        accountReference        = $aRef
        managerAccountReference = $mRef
        managerFallback         = $config.notificationRequesterFallback
        AuditLogs               = [Ref]$auditLogs
    }

    # Add value to request object
    $requestObject += @{
        callerLookup = @{
            id = Get-TopdeskRequesterByType @splatParamsTopdeskCaller
        }
    }

    # Resolve variables in the RequestShort field
    $splatParamsRequestShort = @{
        description       = $template.RequestShort
    }
    $requestShort = Format-Description @splatParamsRequestShort

    #Validate length of RequestShort
    $splatParamsValidateRequestShort = @{
        Description      = $requestShort
        AllowedLength    = 80
        AttributeName    = 'requestShort'
        AuditLogs        = [Ref]$auditLogs
        id               = $pref.id
    }

    Confirm-Description @splatParamsValidateRequestShort
    
    # Add value to request object
    $requestObject += @{
        briefDescription = $requestShort
    }

    # Resolve variables in the RequestDescription field
    $splatParamsRequestDescription = @{
        description       = $template.RequestDescription
    }
    $requestDescription = Format-Description @splatParamsRequestDescription  

    # Add value to request object
    $requestObject += @{
        request = $requestDescription
    }

    # Resolve branch id
    $splatParamsBranch = @{
        AuditLogs       = [ref]$auditLogs
        BaseUrl         = $config.baseUrl
        Headers         = $authHeaders
        Class           = 'Branch'
        Value           = $template.Branch
        Endpoint        = '/tas/api/branches'
        SearchAttribute = 'name'
    }

    # Add branch to request object
    $requestObject += @{
        branch = @{
            id = Get-TopdeskIdentifier @splatParamsBranch
        }
    }
    
    # Resolve operatorgroup id
    if (-not [string]::IsNullOrEmpty($template.OperatorGroup)) {
        $splatParamsOperatorGroup = @{
            AuditLogs       = [ref]$auditLogs
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'OperatorGroup'
            Value           = $template.OperatorGroup
            Endpoint        = '/tas/api/operatorgroups'
            SearchAttribute = 'groupName'
        }

        # Add operatorgroup to request object
        $requestObject += @{
            operatorGroup = @{
                id = Get-TopdeskIdentifier @splatParamsOperatorGroup
            }
        }
    }

     # Resolve operator id 
    if (-not [string]::IsNullOrEmpty($template.Operator)) {
        $splatParamsOperator = @{
            AuditLogs       = [ref]$auditLogs
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'Operator'
            Value           = $template.Operator
            Endpoint        = '/tas/api/operators'
            SearchAttribute = 'email'
        }
    
        #Add Impact to request object
        $requestObject += @{
            operator = @{
                id = Get-TopdeskIdentifier @splatParamsOperator
            }
        }
    }

    # Resolve category id
    if (-not [string]::IsNullOrEmpty($template.Category)) {    
        $splatParamsCategory = @{
            AuditLogs       = [ref]$auditLogs
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'Category'
            Value           = $template.Category
            Endpoint        = '/tas/api/incidents/categories'
            SearchAttribute = 'name'
        }

        # Add category to request object
        $requestObject += @{
            category = @{
                id = Get-TopdeskIdentifier @splatParamsCategory
            }
        }
    }

    # Resolve subCategory id
    if (-not [string]::IsNullOrEmpty($template.SubCategory)) {   
        $splatParamsCategory = @{
            AuditLogs       = [ref]$auditLogs
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'SubCategory'
            Value           = $template.SubCategory
            Endpoint        = '/tas/api/incidents/subcategories'
            SearchAttribute = 'name'
        }

        # Add subCategory to request object
        $requestObject += @{
            subcategory = @{
                id = Get-TopdeskIdentifier @splatParamsCategory
            }
        }
    }

    # Resolve CallType id
    if (-not [string]::IsNullOrEmpty($template.CallType)) {
        $splatParamsCategory = @{
            AuditLogs       = [ref]$auditLogs
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'CallType'
            Value           = $template.CallType
            Endpoint        = '/tas/api/incidents/call_types'
            SearchAttribute = 'name'
        }

        # Add CallType to request object
        $requestObject += @{
            callType = @{
                id = Get-TopdeskIdentifier @splatParamsCategory
            }
        }
    }

    # Resolve Impact id 
    if (-not [string]::IsNullOrEmpty($template.Impact)) {
        $splatParamsCategory = @{
            AuditLogs       = [ref]$auditLogs
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'Impact'
            Value           = $template.Impact
            Endpoint        = '/tas/api/incidents/impacts'
            SearchAttribute = 'name'
        }

        # Add Impact to request object
        $requestObject += @{
            impact = @{
                id = Get-TopdeskIdentifier @splatParamsCategory
            }
        }
    }

    if (-not [string]::IsNullOrEmpty($template.Priority)) {
        # Resolve priority id 
        $splatParamsPriority = @{
            AuditLogs       = [ref]$auditLogs
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'Priority'
            Value           = $template.Priority
            Endpoint        = '/tas/api/incidents/priorities'
            SearchAttribute = 'name'
        }
        

        # Add Impact to request object
        $requestObject += @{
            priority = @{
                id = Get-TopdeskIdentifier @splatParamsPriority
            }
        }
    }

    # Resolve entrytype id 
    if (-not [string]::IsNullOrEmpty($template.EntryType)) {
        $splatParamsEntryType= @{
            AuditLogs       = [ref]$auditLogs
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'EntryType'
            Value           = $template.EntryType
            Endpoint        = '/tas/api/incidents/entry_types'
            SearchAttribute = 'name'
        }
        
        # Add Impact to request object
        $requestObject += @{
            entryType = @{
                id = Get-TopdeskIdentifier @splatParamsEntryType
            }
        }
    }

    # Resolve urgency id 
    if (-not [string]::IsNullOrEmpty($template.Urgency)) {
        $splatParamsUrgency= @{
            AuditLogs       = [ref]$auditLogs
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'Urgency'
            Value           = $template.Urgency
            Endpoint        = '/tas/api/incidents/urgencies'
            SearchAttribute = 'name'
        }
        
        # Add Impact to request object
        $requestObject += @{
            urgency = @{
                id = Get-TopdeskIdentifier @splatParamsUrgency
            }
        }
    }

        # Resolve ProcessingStatus id 
    if (-not [string]::IsNullOrEmpty($template.ProcessingStatus)) {
        $splatParamsProcessingStatus= @{
            AuditLogs       = [ref]$auditLogs
            BaseUrl         = $config.baseUrl
            Headers         = $authHeaders
            Class           = 'ProcessingStatus'
            Value           = $template.ProcessingStatus
            Endpoint        = '/tas/api/incidents/statuses'
            SearchAttribute = 'name'
        }
        
        # Add Impact to request object
        $requestObject += @{
            processingStatus = @{
                id = Get-TopdeskIdentifier @splatParamsProcessingStatus
            }
        }
    }

    if ($auditLogs.isError -contains $true) {
        Throw "Error(s) occured while looking up required values"
    }

#    $auditLogs
    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
            Message = "Grant Topdesk entitlement: [$($pRef.id)] to: [$($p.DisplayName)], will be executed during enforcement"
        })
        Write-Verbose ($requestObject | ConvertTo-Json) 
    }

    if (-not($dryRun -eq $true)) {
        Write-Verbose "Granting TOPdesk entitlement: [$($pRef.id)] to: [$($p.DisplayName)]"

        if (($template.caller -eq 'manager') -and (-not ([string]::IsNullOrEmpty($mRef)))) {
            Write-Verbose "Check if manager is archived"
            # get person (manager)
            $splatParamsPerson = @{
                AccountReference          = $mRef
                AuditLogs                 = [ref]$auditLogs
                Headers                   = $authHeaders
                BaseUrl                   = $config.baseUrl
            }
            $TopdeskPerson = Get-TopdeskPerson  @splatParamsPerson

            if ($TopdeskPerson.status -eq 'personArchived') {
                Write-Verbose "Manager $($TopdeskPerson.id) will be unarchived"
                # Unarchive person (manager)
                $shouldArchive  = $true
                $splatParamsPersonUnarchive = @{
                    TopdeskPerson   = [ref]$TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $config.baseUrl
                    Archive         = $false
                    ArchivingReason = $config.personArchivingReason
                    AuditLogs       = [ref]$auditLogs
                }
                Set-TopdeskPersonArchiveStatus @splatParamsPersonUnarchive
            }
        }
        
        if ($template.caller -eq 'employee') {
            Write-Verbose "Check if employee is archived"
            # get person (employee)
            $splatParamsPerson = @{
                AccountReference          = $aRef
                AuditLogs                 = [ref]$auditLogs
                Headers                   = $authHeaders
                BaseUrl                   = $config.baseUrl
            }
            $TopdeskPerson = Get-TopdeskPerson  @splatParamsPerson
            
            if ($TopdeskPerson.status -eq 'personArchived') {
                Write-Verbose "Employee $($TopdeskPerson.id) will be unarchived"
                # Unarchive person (employee)
                $shouldArchive  = $true
                $splatParamsPersonUnarchive = @{
                    TopdeskPerson   = [ref]$TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $config.baseUrl
                    Archive         = $false
                    ArchivingReason = $config.personArchivingReason
                    AuditLogs       = [ref]$auditLogs
                }
                Set-TopdeskPersonArchiveStatus @splatParamsPersonUnarchive
            }
        }

        # Create incident in Topdesk
        $splatParamsTopdeskIncident = @{
            Headers                 = $authHeaders
            baseUrl                 = $config.baseUrl
            TopdeskIncident          = $requestObject
            AuditLogs               = [Ref]$auditLogs
        }
        $TopdeskIncident = New-TopdeskIncident @splatParamsTopdeskIncident

        if ($shouldArchive -and $TopdeskPerson.status -ne 'personArchived') {
            if (($template.caller -eq 'manager') -and (-not ([string]::IsNullOrEmpty($mRef)))) {
                Write-Verbose "Manager $($TopdeskPerson.id) will be archived"
                $splatParamsPersonArchive = @{
                    TopdeskPerson   = [ref]$TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $config.baseUrl
                    Archive         = $true
                    ArchivingReason = $config.personArchivingReason
                    AuditLogs       = [ref]$auditLogs
                }
                Set-TopdeskPersonArchiveStatus @splatParamsPersonArchive
            }
            if ($template.caller -eq 'employee') {
                Write-Verbose "Employee $($TopdeskPerson.id) will be archived"
                $splatParamsPersonArchive = @{
                    TopdeskPerson   = [ref]$TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $config.baseUrl
                    Archive         = $true
                    ArchivingReason = $config.personArchivingReason
                    AuditLogs       = [ref]$auditLogs
                }
                Set-TopdeskPersonArchiveStatus @splatParamsPersonArchive
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "Grant Topdesk entitlement: [$($pRef.id)] with number [$($TopdeskIncident.number)] was successful."
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
            $message = 'Not creating Topdesk incident, because the notifications are disabled in the connector configuration.'
            $auditLogs.Add([PSCustomObject]@{
                Message = $message
                IsError = $false
            })

        } default {
            #Write-Verbose ($ex | ConvertTo-Json) # Debug - Test
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
