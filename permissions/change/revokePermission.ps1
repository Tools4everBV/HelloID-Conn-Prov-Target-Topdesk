#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Entitlement-Revoke
# PowerShell V2
#####################################################

# The permissionReference object contains the Identification object provided in the retrieve permissions call
$pRef = $actionContext.References.Permission

# To resolve variables in the JSON (compatible with powershell v1 target)
$p = $personContext.Person

# Set debug logging
switch ($($actionContext.Configuration.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Map the account variables used in the JSON
$account = @{
    userPrincipalName = $personContext.Person.Accounts.MicrosoftActiveDirectory.userPrincipalName
    sAMAccountName    = $personContext.Person.Accounts.MicrosoftActiveDirectory.sAMAccountName
    mail              = $personContext.Person.Accounts.MicrosoftActiveDirectory.mail
    TopdeskAssets     = "'EnableGetAssets' not added in JSON or set to false" # Default message shown when using $account.TopdeskAssets
}

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
        $errorMessage = "Could not find revoke entitlement for entitlementSet '$($pRef.id)'. This is likely an issue with the json file."
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
        Throw "Action is not configured"
    }

    Write-Output $entitlementSet.$type
}


function Get-TopdeskTemplateById {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [String]
        $Id
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
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    Write-Output $topdeskTemplate.id
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
                Write-Verbose  "Variable [$var] not found"
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
        $errorMessage = "Could not revoke TOPdesk entitlement [$id]: The attribute [$AttributeName] exceeds the max amount of [$AllowedLength] characters. Please shorten the value for this attribute in the JSON file. Value: [$Description]"
        
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
            $errorMessage = "Could not revoke TOPdesk entitlement: [$($pRef.id)]. Could not set requester: The account reference is empty."
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
        write-verbose "Type: Manager $([string]::IsNullOrEmpty($managerAccountReference))"
        if ([string]::IsNullOrEmpty($managerAccountReference)) {
            write-verbose "Type: Manager - managerAccountReference leeg"
            if ([string]::IsNullOrEmpty($managerFallback)) {
                write-verbose "Type: Manager - managerAccountReference - leeg - fallback leeg"
                $errorMessage = "Could not revoke TOPdesk entitlement: [$($pRef.id)]. Could not set requester: The manager account reference is empty and no fallback email is configured."
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = $errorMessage
                        IsError = $true
                    })
                return
            }
            else {
                write-verbose "Type: Manager - managerAccountReference - leeg - fallback gevuld"
                # Set fallback adress and look it up below
                $type = $managerFallback
            }
        }
        else {
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

function Get-TopdeskChangeType {
    param (
        [string]
        $changeType
    )

    # Show audit message if type is empty
    if ([string]::IsNullOrEmpty($changeType)) {
        $errorMessage = "The change type is not set. It should be set to 'simple' or 'extensive'"
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    # Show audit message if type is not 
    if (-not ($changeType -eq 'simple' -or $changeType -eq 'extensive')) {
        $errorMessage = "The configured change type [$changeType] is invalid. It should be set to 'simple' or 'extensive'"
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        return
    }

    return $ChangeType.ToLower()
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
        [Ref]$TopdeskPerson,

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
            $errorMessage = "Configuration setting 'Archiving Reason' is empty. This is a configuration error."
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
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
            $errorMessage = "Archiving reason [$ArchivingReason] not found in Topdesk"
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
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

function New-TopdeskChange {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [PsObject]
        $TopdeskChange
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

        [Parameter(Mandatory)]
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
                    $assetList += "- $($asset.text)`n"
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
                $assetList += "- $($asset.text)`n"
            }
              
        }
    }

    if ([string]::IsNullOrEmpty($assetList)) {
        if ($SkipNoAssets) {
            Write-Verbose 'Action skipped because no assets are found and [SkipNoAssetsFound = true] is configured'
            return
        }
        else {
            # no results found
            $defaultMessage = $actionContext.Configuration.messageNoAssetsFound
            $assetList = "- $defaultMessage`n"
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

    # Lookup template from json file (C00X)
    $splatParamsHelloIdTopdeskTemplate = @{
        JsonPath = $actionContext.Configuration.notificationJsonPath
        Id       = $pRef.id
        Type     = "Revoke"
    }
    $template = Get-HelloIdTopdeskTemplateById @splatParamsHelloIdTopdeskTemplate
    
    # If template is not empty (both by design or due to an error), process to lookup the information in the template
    if ([string]::IsNullOrEmpty($template)) {
        throw 'HelloID template not found'
    }

    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $actionContext.Configuration.username -ApiKey $actionContext.Configuration.apiKey

    # Lookup Topdesk template id (sja xyz)
    $splatParamsTopdeskTemplate = @{
        Headers = $authHeaders
        BaseUrl = $actionContext.Configuration.baseUrl
        Id      = $template.Template
    }
    $templateId = Get-TopdeskTemplateById @splatParamsTopdeskTemplate

    # Add value to  request object
    $requestObject += @{
        template = @{
            id = $templateId
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

    # Resolve variables in the BriefDescription field
    $splatParamsBriefDescription = @{
        description = $template.BriefDescription
    }
    $briefDescription = Format-Description @splatParamsBriefDescription

    #Validate length of briefDescription
    $splatParamsValidateBriefDescription = @{
        Description   = $briefDescription
        AllowedLength = 80
        AttributeName = 'BriefDescription'
        id            = $pref.id
    }
    Confirm-Description @splatParamsValidateBriefDescription

    # Add value to request object
    $requestObject += @{
        briefDescription = $briefDescription
    }

    # Resolve variables in the request field
    $splatParamsRequest = @{
        description = $template.Request
    }
    $request = Format-Description @splatParamsRequest

    # Add value to request object
    $requestObject += @{
        request = $request
    }

    # Resolve requester
    $splatParamsTopdeskRequester = @{
        Headers                 = $authHeaders
        baseUrl                 = $actionContext.Configuration.baseUrl
        Type                    = $template.Requester
        accountReference        = $actionContext.References.Account 
        managerAccountReference = $actionContext.References.ManagerAccount
        managerFallback         = $actionContext.Configuration.notificationRequesterFallback
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
        changeType = $template.ChangeType
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
    
    if ($outputContext.AuditLogs.IsError -contains $true) {
        throw "Error(s) occured while looking up required values"
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Warning "Revoke Topdesk entitlement: [$($pRef.id)] to: [$($personContext.Person.DisplayName)], will be executed during enforcement"
        Write-Verbose ($requestObject | ConvertTo-Json)
    }

    if (-Not($actionContext.DryRun -eq $true)) {
        Write-Verbose "Revoking TOPdesk entitlement: [$($pRef.id)] to: [$($personContext.Person.DisplayName)]"

        if (($template.Requester -eq 'manager') -and (-not ([string]::IsNullOrEmpty($actionContext.References.ManagerAccount)))) {
            Write-Verbose "Check if manager is archived"
            # get person (manager)
            $splatParamsPerson = @{
                AccountReference = $actionContext.References.ManagerAccount
                Headers          = $authHeaders
                BaseUrl          = $actionContext.Configuration.baseUrl
            }
            $TopdeskPerson = Get-TopdeskPerson  @splatParamsPerson

            if ($TopdeskPerson.status -eq 'personArchived') {
                Write-Verbose "Manager $($TopdeskPerson.id) will be unarchived"
                # Unarchive person (manager)
                $shouldArchive = $true
                $splatParamsPersonUnarchive = @{
                    TopdeskPerson   = [ref]$TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $actionContext.Configuration.baseUrl
                    Archive         = $false
                    ArchivingReason = $actionContext.Configuration.personArchivingReason
                }
                Set-TopdeskPersonArchiveStatus @splatParamsPersonUnarchive
            }
        }
        
        if ($template.Requester -eq 'employee') {
            Write-Verbose "Check if employee is archived"
            # get person (employee)
            $splatParamsPerson = @{
                AccountReference = $actionContext.References.Account 
                Headers          = $authHeaders
                BaseUrl          = $actionContext.Configuration.baseUrl
            }
            $TopdeskPerson = Get-TopdeskPerson  @splatParamsPerson
            
            if ($TopdeskPerson.status -eq 'personArchived') {
                Write-Verbose "Employee $($TopdeskPerson.id) will be unarchived"
                # Unarchive person (employee)
                $shouldArchive = $true
                $splatParamsPersonUnarchive = @{
                    TopdeskPerson   = [ref]$TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $actionContext.Configuration.baseUrl
                    Archive         = $false
                    ArchivingReason = $actionContext.Configuration.personArchivingReason
                }
                Set-TopdeskPersonArchiveStatus @splatParamsPersonUnarchive
            }
        }

        # Create change in Topdesk
        $splatParamsTopdeskChange = @{
            Headers       = $authHeaders
            baseUrl       = $actionContext.Configuration.baseUrl
            TopdeskChange = $requestObject
        }
        $TopdeskChange = New-TopdeskChange @splatParamsTopdeskChange

        if ($shouldArchive -and $TopdeskPerson.status -ne 'personArchived') {
            if (($template.Requester -eq 'manager') -and (-not ([string]::IsNullOrEmpty($actionContext.References.ManagerAccount)))) {
                Write-Verbose "Manager $($TopdeskPerson.id) will be archived"
                $splatParamsPersonArchive = @{
                    TopdeskPerson   = [ref]$TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $actionContext.Configuration.baseUrl
                    Archive         = $true
                    ArchivingReason = $actionContext.Configuration.personArchivingReason
                }
                Set-TopdeskPersonArchiveStatus @splatParamsPersonArchive
            }
            if ($template.Requester -eq 'employee') {
                Write-Verbose "Employee $($TopdeskPerson.id) will be archived"
                $splatParamsPersonArchive = @{
                    TopdeskPerson   = [ref]$TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $actionContext.Configuration.baseUrl
                    Archive         = $true
                    ArchivingReason = $actionContext.Configuration.personArchivingReason
                }
                Set-TopdeskPersonArchiveStatus @splatParamsPersonArchive
            }
        }
        
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Revoking TOPdesk entitlement: [$($pRef.id)] with number [$($TopdeskChange.number)] was successful."
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
                    Message = 'Not creating Topdesk change, because no assets are found and [SkipNoAssetsFound = true] is configured'
                    IsError = $false
                })
        }

        'Notifications are disabled' {
            # Don't do anything when notifications are disabled, mark them as a success
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Not creating Topdesk change, because the notifications are disabled in the connector configuration.'
                    IsError = $false
                })

        } default {
            Write-Verbose ($ex | ConvertTo-Json) # Debug - Test
            if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                $errorMessage = "Could not revoke TOPdesk entitlement: [$($pRef.id)]. Error: $($ex.ErrorDetails.Message)"
            }
            else {
                $errorMessage = "Could not revoke TOPdesk entitlement: [$($pRef.id)]. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
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
