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
        if ([string]::IsNullOrEmpty($accountReference)) {
            $errorMessage = "Could not set requester: The account reference is empty." # add Could not grant TOPdesk entitlement: [$($pRef.id)]
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        } else {
            Write-Output $accountReference
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
    } #else { 
        #Write-Verbose "The length for string [$Description] is [$($Description.Length)] which is shorter than the allowed length [$allowedLength]"
    #}
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
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.WebRequestPSCmdlet') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
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

    # use a single function to retrieve the class objects in Topdesk
    #$classAttribute = $Class                    # required, can't be empty (sorted in the function?)

    # Check if property exists in the template object set in the mapping
    if (-not($Template.PSobject.Properties.Name -Contains $Class)) {
        $errorMessage = "Requested to lookup [$Class], but the [$Value] parameter is missing in the template file"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }
    Write-Verbose "Class [$class]: Variable [$`Value] has value [$($Value)] and endpoint [$($Endpoint)]"

    # Lookup Value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = "$baseUrl$Endpoint"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    $result = $responseGet | Where-object $SearchAttribute -eq $Value

    # When attribute $Class with $Value is not found in Topdesk
    if ([string]::IsNullOrEmpty($result.id)) {
        $errorMessage = "Class [$Class] with value [$Value] isn't found in Topdesk"
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
        Throw "HelloID template with not found"
    }

    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

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
    $splatParamsOperatorGroup = @{
        AuditLogs       = [ref]$auditLogs
        BaseUrl         = $config.baseUrl
        Headers         = $authHeaders
        Class           = 'OperatorGroup'
        Value           = $template.OperatorGroup
        Endpoint        = '/tas/api/operatorgroups'
        SearchAttribute = 'groupname'
    }

    # Add operatorgroup to request object
    $requestObject += @{
        operatorGroup = @{
            id = Get-TopdeskIdentifier @splatParamsOperatorGroup
        }
    }
 
    # Resolve category id
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

    # Resolve subCategory id
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

    # Resolve CallType id
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

    # Resolve Impact id 
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

    # # Resolve operator id 
    # $splatParamsOperator = @{
    #     AuditLogs       = [ref]$auditLogs
    #     BaseUrl         = $config.baseUrl
    #     Headers         = $authHeaders
    #     Class           = 'Operator'
    #     Value           = $template.Operator
    #     Endpoint        = '/tas/api/operators'
    #     SearchAttribute = 'email'
    # }
    
    # # Add Impact to request object
    # $requestObject += @{
    #     operator = @{
    #         id = Get-TopdeskIdentifier @splatParamsOperator
    #     }
    # }

    # Resolve entrytype id 
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

    # Resolve urgency id 
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

    # Resolve caller
    $splatParamsTopdeskCaller = @{
        Headers                 = $authHeaders
        baseUrl                 = $config.baseUrl
        Type                    = $template.caller
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

        # Create incident in Topdesk
        $splatParamsTopdeskIncident = @{
            Headers                 = $authHeaders
            baseUrl                 = $config.baseUrl
            TopdeskIncident          = $requestObject
            AuditLogs               = [Ref]$auditLogs
        }
        $TopdeskIncident = New-TopdeskIncident @splatParamsTopdeskIncident

        # manager / employee unarchive / archive needs to be added
        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "Grant Topdesk entitlement: [$($pRef.id)] with number [$($incident.number)] was successful."
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
