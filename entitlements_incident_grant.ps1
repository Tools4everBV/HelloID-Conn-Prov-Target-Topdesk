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
        $TopdeskIncident
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
        $Template,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Class,
        [Parameter()]
        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
        # Add a required/optional parameter?
    )
    # Configure endpoints for extra classes here (move to top of script?)
    $classEndpoints =  [PSCustomObject]@{
        Branch        = '/tas/api/branches'
        OperatorGroup = '/tas/api/operatorgroups'
        Category      = '/tas/api/incidents/categories'
        SubCategory   = '/tas/api/incidents/subcategories'
        CallType      = '/tas/api/incidents/call_types'
        Impact        = '/tas/api/incidents/impacts'
        priority      = '/tas/api/incidents/priorities'
    }

    # use a single function to retrieve the class objects in Topdesk
    $classAttribute = $Class                    # required, can't be empty (sorted in the function?)
    $classValue     = $($Template.$Class)       # required? can it be empty?
    $classEndpoint  = $($classEndpoints.$Class) # required!

    # Check if property exists in the template object set in the mapping
    if (-not($Template.PSobject.Properties.Name -Contains $classAttribute)) {
        $errorMessage = "Requested to lookup [$classAttribute], but the [$classAttribute] parameter is missing in the template file"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }
    write-verbose "Class [$class]: Variable [$`Template.$classAttribute] has value [$($Template.$classAttribute)] and endpoint [$($classEndpoints.$classAttribute)]"
    $classEndpoint

    # Lookup Value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = "$baseUrl$classEndpoint"
        Method  = 'GET'
        Headers = $Headers
    }
    $splatParams
    $responseGet = Invoke-TopdeskRestMethod @splatParams
    $result = $responseGet | Where-object name -eq $classValue

    # When attribute $classAttribute with $classValue is not found in Topdesk
    if ([string]::IsNullOrEmpty($result.id)) {
        $errorMessage = "Class [$classAttribute] with value [$classValue] isn't found in Topdesk"
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    } else {
        # $id is found in Topdesk, set in Topdesk
        $Template.$classAttribute = $result.id
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
        Template        = $template
        AuditLogs       = [ref]$auditLogs
        Headers         = $authHeaders
        baseUrl         = $config.baseUrl
        class           = 'Branch'
    }
    Get-TopdeskIdentifier @splatParamsBranch

    # Add branch to request object
    $requestObject += @{
        branch = @{
            id = $template.branch
        }
    }

    # Resolve operatorgroup id
    $splatParamsOperatorGroup = @{
        Template        = $template
        AuditLogs       = [ref]$auditLogs
        Headers         = $authHeaders
        baseUrl         = $config.baseUrl
        class           = 'OperatorGroup'
    }
    Get-TopdeskIdentifier @splatParamsOperatorGroup

    # Add operatorgroup to request object
    $requestObject += @{
        operatorGroup = @{
            id = $template.operatorGroup
        }
    }

    # Resolve category id
    $splatParamsCategory = @{
        Template        = $template
        AuditLogs       = [ref]$auditLogs
        Headers         = $authHeaders
        baseUrl         = $config.baseUrl
        class           = 'Category'
    }
    Get-TopdeskIdentifier @splatParamsCategory

    # Add category to request object
    $requestObject += @{
        category = @{
            id = $template.category
        }
    }

    # Resolve subCategory id
    $splatParamsCategory = @{
        Template         = $template
        AuditLogs       = [ref]$auditLogs
        Headers         = $authHeaders
        baseUrl         = $config.baseUrl
        class           = 'SubCategory'
    }
    Get-TopdeskIdentifier @splatParamsCategory

    # Add subCategory to request object
    $requestObject += @{
        subcategory = @{
            id = $template.subCategory
        }
    }

    # Resolve CallType id
    $splatParamsCategory = @{
        Template         = $template
        AuditLogs       = [ref]$auditLogs
        Headers         = $authHeaders
        baseUrl         = $config.baseUrl
        class           = 'CallType'
    }
    Get-TopdeskIdentifier @splatParamsCategory
    # Add CallType to request object
    $requestObject += @{
        callType = @{
            id = $template.CallType
        }
    }

    # Resolve Impact id 
    $splatParamsCategory = @{
        Template         = $template
        AuditLogs       = [ref]$auditLogs
        Headers         = $authHeaders
        baseUrl         = $config.baseUrl
        class           = 'Impact'
    }
    Get-TopdeskIdentifier @splatParamsCategory
    # Add Impact to request object
    $requestObject += @{
        impact = @{
            id = $template.Impact
        }
    }

    # Resolve priority id 
    $splatParamsPriority = @{
        Template         = $template
        AuditLogs       = [ref]$auditLogs
        Headers         = $authHeaders
        baseUrl         = $config.baseUrl
        class           = 'priority'
    }
    Get-TopdeskIdentifier @splatParamsPriority
    # Add Impact to request object
    $requestObject += @{
        priority = @{
            id = $template.Priority
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
    $callerId = Get-TopdeskRequesterByType @splatParamsTopdeskCaller

    # Add value to request object
    $requestObject += @{
        callerLookup = @{
            id = $callerId
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

    # Resolve variables in the BriefDescription field
    $splatParamsBriefDescription = @{
        description       = $template.RequestDescription
    }
    $briefDescription = Format-Description @splatParamsBriefDescription

    # Add value to request object
    $requestObject += @{
        request = $briefDescription
    }

    if ($auditLogs.isError -contains $true) {
        Throw "Error(s) occured while looking up required values"
    }

<#
    "CallerEmail": "tester@test.com", # renamed to caller // done
    "RequestShort": "Aanvraag Laptop ($($p.displayName))", // done
    "RequestDescription": "Graag een laptop gereed maken voor onderstaande medewerker.\n\nNaam: $($p.Name.NickName)\nAchternaam: $($p.Name.FamilyName)\nPersoneelsnummer: $($p.ExternalId)\n\nFunctie: $($p.PrimaryContract.Title.Name)\nAfdeling: $($p.PrimaryContract.Department.DisplayName)", // done
    "Branch" // DONE
    "OperatorGroup": "Servicedesk",  // done
    "Category": "Middelen", // done
    "SubCategory": "Inventaris & apparatuur", //done
    "CallType": "Aanvraag",
    "Impact": "Organisatie",
    "CloseTicket": true
#>

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
            TopdeskIncident           = $requestObject
            AuditLogs               = [Ref]$auditLogs
        }
        $TopdeskIncident = New-TopdeskIncident @splatParamsTopdeskIncident

        # manager / employee unarchive / archive needs to be added
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