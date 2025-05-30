#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Entitlement-Grant-Incident
# PowerShell V2
#####################################################

# The permissionReference object contains the Identification object provided in the retrieve permissions call
$pRef = $actionContext.References.Permission

# To resolve variables in the JSON (compatible with powershell v1 target)
$p = $personContext.Person

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Map the account variables used in the JSON
$account = @{
    userPrincipalName = $personContext.Person.Accounts.MicrosoftActiveDirectory.userPrincipalName
    sAMAccountName    = $personContext.Person.Accounts.MicrosoftActiveDirectory.sAMAccountName
    mail              = $personContext.Person.Accounts.MicrosoftActiveDirectory.mail
    TopdeskAssets     = "'EnableGetAssets' not added in JSON or set to false" # Default message shown when using $account.TopdeskAssets
}

#region helperfunctions
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

function Get-HelloIdTopdeskTemplateById {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $JsonPath,

        [ValidateNotNullOrEmpty()]
        [string]
        $Id,

        [ValidateNotNullOrEmpty()]
        [string]
        $Type
    )

    # Check if file exists.
    try {
        $permissionList = Get-Content -Raw -Encoding utf8 -Path $JsonPath | ConvertFrom-Json
    }
    catch {
        $ex = $PSItem
        $errorMessage = "Could not retrieve Topdesk permissions file. Error: $($ex.Exception.Message)"
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    # Check if entitlement with id exists
    $entitlementSet = $permissionList | Where-Object { ($_.Identification.id -eq $pRef.id) }
    if ([string]::IsNullOrEmpty($entitlementSet)) {
        $errorMessage = "Could not find entitlement set with id '$($pRef.id)'. This is likely an issue with the json file."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    # Check if entitlement with id and specific type exists
    if (-not($entitlementSet.PSObject.Properties.Name -Contains $type)) {
        $errorMessage = "Could not find grant entitlement for entitlementSet '$($pRef.id)'. This is likely an issue with the json file."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    # If empty, nothing should be done.
    if ([string]::IsNullOrEmpty($entitlementSet.$type)) {
        $message = "Action '$type' for entitlement '$($pRef.id)' is not configured."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $message
                IsError = $false
            })
        return
    }

    Write-Output $entitlementSet.$type
}

function Get-VariablesFromString {
    param(
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
    param(
        [ref]
        $String,

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
            }
            elseif ($null -ne $curObject.$_) {
                $String.Value = $String.Value.Replace($var, $curObject.$_)
            }
            else {
                Write-Information  "Variable [$var] not found"
                $String.Value = $String.Value.Replace($var, $curObject.$_) # Add to override unresolved variables with null
            }
        }
    }
}

function Format-Description {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Description
    )
    try {
        $variablesFound = Get-VariablesFromString -String $Description
        Resolve-Variables -String ([ref]$Description) -VariablesToResolve $variablesFound

        Write-Output $Description
    }
    catch {
        throw $_
    }
}

function Confirm-Description {
    param (
        [ValidateNotNullOrEmpty()]
        [String]
        $Description,

        [ValidateNotNullOrEmpty()]
        [String]
        $AttributeName,

        [ValidateNotNullOrEmpty()]
        [String]
        $id,

        [ValidateNotNullOrEmpty()]
        [String]
        $AllowedLength
    )
    if ($Description.Length -gt $AllowedLength) {
        $errorMessage = "Could not grant TOPdesk entitlement [$id]: The attribute [$AttributeName] exceeds the max amount of [$AllowedLength] characters. Please shorten the value for this attribute in the JSON file. Value: [$Description]"
        
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
    }
}

function Get-TopdeskRequesterByType {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [string]
        $Type,

        [string]
        $accountReference,

        [string]
        $managerAccountReference,

        [string]
        $managerFallback
    )

    # Validate employee entry
    if ($type -eq 'employee') {
        if ([string]::IsNullOrEmpty($accountReference)) {
            $errorMessage = "Could not grant TOPdesk entitlement: [$($pRef.id)]. Could not set requester: The account reference is empty."
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
        }
        else {
            Write-Output $accountReference
        }
        return
    }

    # Validate employee entry
    if ($type -eq 'manager') {
        Write-Information "Type: Manager $([string]::IsNullOrEmpty($managerAccountReference))"
        if ([string]::IsNullOrEmpty($managerAccountReference)) {
            Write-Information "Type: Manager - managerAccountReference empty"
            if ([string]::IsNullOrEmpty($managerFallback)) {
                Write-Information "Type: Manager - managerAccountReference - empty - fallback empty"
                $errorMessage = "Could not grant TOPdesk entitlement: [$($pRef.id)]. Could not set requester: The manager account reference is empty and no fallback email is configured."
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = $errorMessage
                        IsError = $true
                    })
                return
            }
            else {
                Write-Information "Type: Manager - managerAccountReference - empty - fallback filled"
                # Set fallback adress and look it up below
                $type = $managerFallback
            }
        }
        else {
            Write-Information "Type: Manager - managerAccountReference - filled: [$managerAccountReference]"
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
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    # Check if only one result is returned
    if ([string]::IsNullOrEmpty($responseGet.id)) {

        # no results found
        $errorMessage = "Could not set requester: Topdesk person with email [$Type] not found."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }
    elseif ($responseGet.Count -eq 1) {

        # one record found, correlate, return id
        write-output $responseGet.id
    }
    else {

        # Multiple records found, correlation
        $errorMessage = "Multiple [$($responseGet.Count)] persons found with Email address [$Email]. Login names: [$($responseGet.tasLoginName)]"
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
    }
}

function Get-TopdeskPersonById {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

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
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [String]
        $AccountReference
    )

    # Check if the account reference is empty, if so, generate audit message
    if ([string]::IsNullOrEmpty($AccountReference)) {

        # throw an error when account reference is empty
        $errorMessage = "The account reference is empty. This is a scripting issue."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    # AcountReference is available, query person
    $splatParams = @{
        Headers         = $Headers
        BaseUrl         = $BaseUrl
        PersonReference = $AccountReference
    }
    $person = Get-TopdeskPersonById @splatParams

    if ([string]::IsNullOrEmpty($person)) {
        $errorMessage = "Person with reference [$AccountReference)] is not found. If the person is deleted, you might need to regrant the account entitlement."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
    }
    else {
        Write-Output $person
    }
}

function Set-TopdeskPersonArchiveStatus {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [Object]
        $TopdeskPerson,

        [ValidateNotNullOrEmpty()]
        [Bool]
        $Archive,

        [String]
        $ArchivingReason
    )

    # Set ArchiveStatus variables based on archive parameter
    if ($Archive -eq $true) {

        #When the 'archiving reason' setting is not configured in the target connector configuration
        if ([string]::IsNullOrEmpty($ArchivingReason)) {
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Configuration setting 'Archiving Reason' is empty. This is a configuration error."
                    IsError = $true
                })
            throw "Error(s) occured while looking up required values"
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
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Archiving reason [$ArchivingReason] not found in Topdesk"
                    IsError = $true
                })
            throw "Error(s) occured while looking up required values"
        }
        $archiveStatus = 'personArchived'
        $archiveUri = 'archive'
        $body = @{ id = $archivingReasonObject.id }
    }
    else {
        $archiveStatus = 'person'
        $archiveUri = 'unarchive'
        $body = $null
    }

    # Archive / unarchive person
    Write-Information "[$archiveUri] person with id [$($TopdeskPerson.id)]"
    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/persons/id/$($TopdeskPerson.id)/$archiveUri"
        Method  = 'PATCH'
        Headers = $Headers
        Body    = $body | ConvertTo-Json
    }
    $null = Invoke-TopdeskRestMethod @splatParams
    return $archiveStatus
}

function Get-TopdeskIdentifier {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers, 

        [string]
        $Class,    

        [ValidateNotNullOrEmpty()]
        [Object]
        $Value,

        [ValidateNotNullOrEmpty()]
        [Object]
        $Endpoint,

        [ValidateNotNullOrEmpty()]
        [Object]
        $SearchAttribute
    )

    # Check if property exists in the template object set in the mapping
    if (-not($Template.PSobject.Properties.Name -Contains $Class)) {
        $errorMessage = "Requested to lookup [$Class], but the [$Value] parameter is missing in the template file"
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }
    
    Write-Information "Class [$class]: Variable [$`Value] has value [$($Value)] and endpoint [$($Endpoint)?query=$($SearchAttribute)==$($Value))]"

    # Lookup Value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = $baseUrl + $Endpoint + "?query=" + $SearchAttribute + "==" + "'$Value'"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    $result = $responseGet | Where-object $SearchAttribute -eq $Value

    # When attribute $Class with $Value is not found in Topdesk
    if ([string]::IsNullOrEmpty($result.id)) {
        $errorMessage = "Class [$Class] with SearchAttribute [$SearchAttribute] with value [$Value] isn't found in Topdesk"
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            }) 
    }
    else {
        # $id is found in Topdesk, set in Topdesk
        Write-Output $result.id
    }
}

function New-TopdeskIncident {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

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
    Write-Information ($TopdeskIncident | ConvertTo-Json)

    $incident = Invoke-TopdeskRestMethod @splatParams

    Write-Information "Created incident with number [$($incident.number)]"

    Write-Output $incident
}

function Get-TopdeskAssetsByPersonId {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [String]
        $PersonId,

        [Parameter()]
        [Array]
        $AssetFilter,
        
        [Parameter()]
        [Boolean]
        $SkipNoAssets
    )

    # Check if the correlationAttribute is not empty
    if ([string]::IsNullOrEmpty($PersonId)) {
        $errorMessage = "The person ID [$PersonId] is empty. This is likely a scripting issue."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    if ($AssetFilter) {
        foreach ($item in $AssetFilter) {
            # Lookup value is filled in, lookup value in Topdesk
            $splatParams = @{
                Uri     = "$baseUrl/tas/api/assetmgmt/assets?archived='false'&templateName=$item&linkedTo=person/$PersonId"
                Method  = 'GET'
                Headers = $Headers
            }

            $responseGet = Invoke-TopdeskRestMethod @splatParams

            # Check if no results are returned
            if ($responseGet.dataSet.Count -gt 0) {
                # records found, filter out archived assets and return
                foreach ($asset in $responseGet.dataSet) {
                    $assetList += "- $($asset.text)<br>"
                }
            }
        }   
    }
    else {
        # Lookup value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/assetmgmt/assets?archived='false'&linkedTo=person/$PersonId"
            Method  = 'GET'
            Headers = $Headers
        }

        $responseGet = Invoke-TopdeskRestMethod @splatParams

        # Check if no results are returned
        if ($responseGet.dataSet.Count -gt 0) {
            # records found, filter out archived assets and return
            foreach ($asset in $responseGet.dataSet) {
                $assetList += "- $($asset.text)<br>"
            }
              
        }
    }
    
    if ([string]::IsNullOrEmpty($assetList)) {
        if ($SkipNoAssets) {
            Write-Information 'Action skipped because no assets are found and [SkipNoAssetsFound = true] is configured'
            return
        }
        else {
            # no results found
            $defaultMessage = $actionContext.Configuration.messageNoAssetsFound
            $assetList = "- $defaultMessage<br>"
        }
    }
    write-output $assetList
}
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    if ($actionContext.Configuration.disableNotifications -eq 'true') {
        throw "Notifications are disabled"
    }

    $requestObject = @{}
    # Lookup template from json file (C00X)
    $splatParamsHelloIdTopdeskTemplate = @{
        JsonPath = $actionContext.Configuration.notificationJsonPath
        Id       = $pRef.id
        Type     = "Grant"
    }
    $template = Get-HelloIdTopdeskTemplateById @splatParamsHelloIdTopdeskTemplate

    # If template is not empty (both by design or due to an error), process to lookup the information in the template
    if ([string]::IsNullOrEmpty($template)) {
        throw 'HelloID template not found'
    }

    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $actionContext.Configuration.username -ApiKey $actionContext.Configuration.apiKey

    # Resolve caller
    $splatParamsTopdeskCaller = @{
        Headers                 = $authHeaders
        BaseUrl                 = $actionContext.Configuration.baseUrl
        Type                    = $template.Caller
        accountReference        = $actionContext.References.Account 
        managerAccountReference = $actionContext.References.ManagerAccount
        managerFallback         = $actionContext.Configuration.notificationRequesterFallback
    }

    # Add value to request object
    $requestObject += @{
        callerLookup = @{
            id = Get-TopdeskRequesterByType @splatParamsTopdeskCaller
        }
    }

    # Lookup Assets of person
    if ($template.EnableGetAssets) {
        # Only use the filter if it is defined in the JSON
        if ($template.PSObject.Properties.Name -Contains 'AssetsFilter') {
            $templateFilters = $($template.AssetsFilter).Split(",") #TemplateName, case sensitive
        }
        else {
            $templateFilters = ""
        }
            
        # get assets of employee
        $splatParamsTopdeskAssets = @{
            PersonId     = $actionContext.References.Account 
            Headers      = $authHeaders
            BaseUrl      = $actionContext.Configuration.baseUrl
            AssetFilter  = $templateFilters
            SkipNoAssets = [boolean]$template.SkipNoAssetsFound
        }
    
        # Use $($account.TopdeskAssets) in your notification configuration to resolve the queried assets
        $account.TopdeskAssets = Get-TopdeskAssetsByPersonId @splatParamsTopdeskAssets

        # TopdeskAssets can only be empty if the action needs to be skiped [SkipNoAssetsFound = true]
        if ([string]::IsNullOrEmpty($account.TopdeskAssets)) {
            throw 'Action skip'
        }
    }

    # Resolve variables in the RequestShort field
    $splatParamsRequestShort = @{
        description = $template.RequestShort
    }
    $requestShort = Format-Description @splatParamsRequestShort

    #Validate length of RequestShort
    $splatParamsValidateRequestShort = @{
        Description   = $requestShort
        AllowedLength = 80
        AttributeName = 'requestShort'
        id            = $pref.id
    }

    Confirm-Description @splatParamsValidateRequestShort
    
    # Add value to request object
    $requestObject += @{
        briefDescription = $requestShort
    }

    # Resolve variables in the RequestDescription field
    $splatParamsRequestDescription = @{
        description = $template.RequestDescription
    }
    $requestDescription = Format-Description @splatParamsRequestDescription

    # Add value to request object
    $requestObject += @{
        request = $requestDescription
    }

    # Resolve variables in the Action field
    if (-not [string]::IsNullOrEmpty($template.Action)) {
        $splatParamsAction = @{
            description = $template.Action
        }
        $requestAction = Format-Description @splatParamsAction

        # Add value to request object
        $requestObject += @{
            action = $requestAction
        }
    }

    # Resolve branch id
    $splatParamsBranch = @{
        BaseUrl         = $actionContext.Configuration.baseUrl
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
            BaseUrl         = $actionContext.Configuration.baseUrl
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
            BaseUrl         = $actionContext.Configuration.baseUrl
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
            BaseUrl         = $actionContext.Configuration.baseUrl
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
            BaseUrl         = $actionContext.Configuration.baseUrl
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
            BaseUrl         = $actionContext.Configuration.baseUrl
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
            BaseUrl         = $actionContext.Configuration.baseUrl
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

    # Resolve priority id 
    if (-not [string]::IsNullOrEmpty($template.Priority)) {
        $splatParamsPriority = @{
            BaseUrl         = $actionContext.Configuration.baseUrl
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

    # Resolve duration id 
    if (-not [string]::IsNullOrEmpty($template.Duration)) {
        $splatParamsDuration = @{
            BaseUrl         = $actionContext.Configuration.baseUrl
            Headers         = $authHeaders
            Class           = 'Duration'
            Value           = $template.Duration
            Endpoint        = '/tas/api/incidents/durations'
            SearchAttribute = 'name'
        }
        
        # Add Impact to request object
        $requestObject += @{
            duration = @{
                id = Get-TopdeskIdentifier @splatParamsDuration
            }
        }
    }

    # Resolve entrytype id 
    if (-not [string]::IsNullOrEmpty($template.EntryType)) {
        $splatParamsEntryType = @{
            BaseUrl         = $actionContext.Configuration.baseUrl
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
        $splatParamsUrgency = @{
            BaseUrl         = $actionContext.Configuration.baseUrl
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
        $splatParamsProcessingStatus = @{
            BaseUrl         = $actionContext.Configuration.baseUrl
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

    # Add status to request object
    if (-not [string]::IsNullOrEmpty($template.Status)) {
        $requestObject += @{
            status = $template.Status
        }
    }

    if ($outputContext.AuditLogs.IsError -contains $true) {
        throw "Error(s) occured while looking up required values"
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Warning "Grant Topdesk entitlement: [$($pRef.id)] to: [$($personContext.Person.DisplayName)], will be executed during enforcement"
          
        Write-Information ($requestObject | ConvertTo-Json) 
    }

    if (-Not($actionContext.DryRun -eq $true)) {
        Write-Information "Granting TOPdesk entitlement: [$($pRef.id)] to: [$($personContext.Person.DisplayName)]"

        if (($template.caller -eq 'manager') -and (-not ([string]::IsNullOrEmpty($actionContext.References.ManagerAccount)))) {
            # get person (manager)
            $splatParamsPerson = @{
                AccountReference = $actionContext.References.ManagerAccount
                Headers          = $authHeaders
                BaseUrl          = $actionContext.Configuration.baseUrl
            }
            $TopdeskPerson = Get-TopdeskPerson  @splatParamsPerson

            if ($TopdeskPerson.status -eq 'personArchived') {
                # Unarchive person (manager)
                $shouldArchive = $true
                $splatParamsPersonUnarchive = @{
                    TopdeskPerson   = $TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $actionContext.Configuration.baseUrl
                    Archive         = $false
                    ArchivingReason = $actionContext.Configuration.personArchivingReason
                }
                $null = Set-TopdeskPersonArchiveStatus @splatParamsPersonUnarchive
            }
        }
        
        if ($template.caller -eq 'employee') {
            # get person (employee)
            $splatParamsPerson = @{
                AccountReference = $actionContext.References.Account 
                Headers          = $authHeaders
                BaseUrl          = $actionContext.Configuration.baseUrl
            }
            $TopdeskPerson = Get-TopdeskPerson  @splatParamsPerson
            
            if ($TopdeskPerson.status -eq 'personArchived') {
                # Unarchive person (employee)
                $shouldArchive = $true
                $splatParamsPersonUnarchive = @{
                    TopdeskPerson   = $TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $actionContext.Configuration.baseUrl
                    Archive         = $false
                    ArchivingReason = $actionContext.Configuration.personArchivingReason
                }
                $null = Set-TopdeskPersonArchiveStatus @splatParamsPersonUnarchive
            }
        }

        # Create incident in Topdesk
        $splatParamsTopdeskIncident = @{
            Headers         = $authHeaders
            baseUrl         = $actionContext.Configuration.baseUrl
            TopdeskIncident = $requestObject
        }
        $TopdeskIncident = New-TopdeskIncident @splatParamsTopdeskIncident

        if ($shouldArchive) {
            if (($template.caller -eq 'manager') -and (-not ([string]::IsNullOrEmpty($actionContext.References.ManagerAccount)))) {
                $splatParamsPersonArchive = @{
                    TopdeskPerson   = $TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $actionContext.Configuration.baseUrl
                    Archive         = $true
                    ArchivingReason = $actionContext.Configuration.personArchivingReason
                }
                $null = Set-TopdeskPersonArchiveStatus @splatParamsPersonArchive
            }
            if ($template.caller -eq 'employee') {
                $splatParamsPersonArchive = @{
                    TopdeskPerson   = $TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $actionContext.Configuration.baseUrl
                    Archive         = $true
                    ArchivingReason = $actionContext.Configuration.personArchivingReason
                }
                $null = Set-TopdeskPersonArchiveStatus @splatParamsPersonArchive
            }
        }

        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Granting Topdesk entitlement: [$($pRef.id)]. Created incident with number [$($TopdeskIncident.number)]."
                IsError = $false
            })
    }
}
catch {
    $ex = $PSItem

    switch ($ex.Exception.Message) {

        'HelloID Template not found' {
            # Only log when there are no lookup values, as these generate their own audit message, set success based on error state
        }

        'Error(s) occured while looking up required values' {
            # Only log when there are no lookup values, as these generate their own audit message
        }

        'Action skip' {
            # If empty and [SkipNoAssetsFound = true] in the JSON, nothing should be done. Mark them as a success
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Not creating Topdesk incident, because no assets are found and [SkipNoAssetsFound = true] is configured'
                    IsError = $false
                })
        }

        'Notifications are disabled' {
            # Don't do anything when notifications are disabled, mark them as a success
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Not creating Topdesk incident, because the notifications are disabled in the connector configuration.'
                    IsError = $false
                })

        } default {
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorMessage = "Could not grant Topdesk entitlement: [$($pRef.id)]. Error: $($ex.ErrorDetails.Message)"
            }
            else {
                $errorMessage = "Could not grant Topdesk entitlement: [$($pRef.id)]. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
            }
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
        }
    }
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if ($outputContext.AuditLogs.IsError -notContains $true) {
        $outputContext.Success = $true
    }
}
