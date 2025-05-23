#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Update
# PowerShell V2
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function ConvertTo-TopDeskFlatObject {
    param (
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Object,
        [string] $Prefix = ""
    )
 
    $result = [ordered]@{}
 
    foreach ($property in $Object.PSObject.Properties) {
        $name = if ($Prefix) { "$Prefix`_$($property.Name)" } else { $property.Name }
 
        if ($property.Value -is [pscustomobject]) {
            $flattenedSubObject = ConvertTo-TopDeskFlatObject -Object $property.Value -Prefix $name
            foreach ($subProperty in $flattenedSubObject.PSObject.Properties) {
                $result[$subProperty.Name] = [string]$subProperty.Value
            }
        }
        else {
            $result[$name] = [string]$property.Value
        }
    }
 
    [PSCustomObject]$result
}

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

function Get-TopdeskBranch {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [Object]
        [ref]$Account
    )

    # Check if branch.name property exists in the account object set in the mapping
    if (-not($account.branch.PSObject.Properties.Name -Contains 'name')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Requested to lookup branch, but branch.name is missing. This is a mapping issue."
                IsError = $true
            })
        return
    }
        
    if ([string]::IsNullOrEmpty($Account.branch.name)) {
        # As branch is always a required field,  no branch in lookup value = error
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "The lookup value for Branch is empty but it's a required field."
                IsError = $true
            })
    }
    else {
        # Lookup Value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/branches"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-TopdeskRestMethod @splatParams
        $branch = $responseGet | Where-object name -eq $Account.branch.name
        # When branch is not found in Topdesk
        if ([string]::IsNullOrEmpty($branch.id)) {
            # As branch is a required field, if no branch is found, an error is logged
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Branch with name [$($Account.branch.name)] isn't found in Topdesk but it's a required field."
                    IsError = $true
                })
        }
        else {
            # Branch is found in Topdesk, set in Topdesk
            $Account.branch.PSObject.Properties.Remove('name')
            $Account.branch | Add-Member -MemberType NoteProperty -Name 'id' -Value $branch.id
        }
    }
}
function Get-TopdeskDepartment {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        $LookupErrorHrDepartment,

        [ValidateNotNullOrEmpty()]
        $LookupErrorTopdesk,

        [ValidateNotNullOrEmpty()]
        [Object]
        [ref]$Account
    )

    # Check if department.name property exists in the account object set in the mapping
    if (-not($Account.department.PSObject.Properties.Name -Contains 'name')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Requested to lookup department, but department.name is not set. This is a mapping issue."
                IsError = $true
            })
        return
    }
    # When department.name is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($Account.department.name)) {
        if ([System.Convert]::ToBoolean($LookupErrorHrDepartment)) {
            # True, no department in lookup value = throw error
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "The lookup value for Department is empty and the connector is configured to stop when this happens."
                    IsError = $true
                })
        }
        else {
            # False, no department in lookup value = clear value
            Write-Information "Clearing department. (lookupErrorHrDepartment = False)"
            $Account.department.PSObject.Properties.Remove('name')
            $Account.department | Add-Member -NotePropertyName id -NotePropertyValue $null
        }
    }
    else {
        # Lookup Value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/departments"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-TopdeskRestMethod @splatParams
        $department = $responseGet | Where-object name -eq $Account.department.name

        # When department is not found in Topdesk
        if ([string]::IsNullOrEmpty($department.id)) {
            if ([System.Convert]::ToBoolean($LookupErrorTopdesk)) {
                # True, no department found = throw error
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Department [$($Account.department.name)] not found in Topdesk and the connector is configured to stop when this happens."
                        IsError = $true
                    })
            }
            else {
                # False, no department found = remove department field (leave empty on creation or keep current value on update)
                $Account.department.PSObject.Properties.Remove('name')
                $Account.PSObject.Properties.Remove('department')
                Write-Information "Not overwriting or setting department as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        }
        else {
            # Department is found in Topdesk, set in Topdesk
            $Account.department.PSObject.Properties.Remove('name')
            $Account.department | Add-Member -MemberType NoteProperty -Name 'id' -Value $department.id
            # $Account.department.Add('id', $department.id)
        }
    }
}

function Get-TopdeskBudgetHolder {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        $LookupErrorHrBudgetHolder,

        [ValidateNotNullOrEmpty()]
        $LookupErrorTopdesk,

        [ValidateNotNullOrEmpty()]
        [Object]
        [ref]$Account
    )

    # Check if budgetholder.name property exists in the account object set in the mapping
    if (-not($Account.budgetHolder.PSObject.Properties.Name -Contains 'name')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Requested to lookup budgetholder, but budgetholder.name is missing. This is a mapping issue."
                IsError = $true
            })
        return
    }

    # When budgetholder.name is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($Account.budgetHolder.name)) {
        if ([System.Convert]::ToBoolean($lookupErrorHrBudgetHolder)) {
            # True, no budgetholder in lookup value = throw error
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "The lookup value for budgetholder is empty and the connector is configured to stop when this happens."
                    IsError = $true
                })
        }
        else {
            # False, no budgetholder in lookup value = clear value
            Write-Information "Clearing budgetholder. (lookupErrorHrBudgetHolder = False)"
            $Account.budgetHolder.PSObject.Properties.Remove('name')
            $Account.budgetHolder | Add-Member -NotePropertyName id -NotePropertyValue $null
        }
    }
    else {

        # Lookup Value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$BaseUrl/tas/api/budgetholders"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-TopdeskRestMethod @splatParams
        $budgetHolder = $responseGet | Where-object name -eq $Account.budgetHolder.name

        # When budgetholder is not found in Topdesk
        if ([string]::IsNullOrEmpty($budgetHolder.id)) {
            if ([System.Convert]::ToBoolean($lookupErrorTopdesk)) {
                # True, no budgetholder found = throw error
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Budgetholder [$($Account.budgetHolder.name)] not found in Topdesk and the connector is configured to stop when this happens."
                        IsError = $true
                    })
            }
            else {
                # False, no budgetholder found = remove budgetholder field (leave empty on creation or keep current value on update)
                $Account.budgetHolder.PSObject.Properties.Remove('name')
                $Account.PSObject.Properties.Remove('budgetHolder')
                Write-Information "Not overwriting or setting budgetholder as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        }
        else {
            # Budgetholder is found in Topdesk, set in Topdesk
            $Account.budgetHolder.PSObject.Properties.Remove('name')
            $Account.budgetHolder | Add-Member -MemberType NoteProperty -Name 'id' -Value $budgetHolder.id
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
    try {
        # Lookup value is filled in, lookup person in Topdesk
        $splatParams = @{
            Uri     = "$BaseUrl/tas/api/persons/id/$PersonReference"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-TopdeskRestMethod @splatParams
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            $responseGet = $null
        }
        else {
            throw
        }
    }
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
        Write-Warning "The account reference is empty. This is a scripting issue."
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "The account reference is empty. This is a scripting issue."
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
    Write-Output $person
}

function Get-TopdeskPersonManager {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [Object]
        [Ref]$Account
    )

    # Check if manager.id property exists in the account object set in the mapping
    if (-not($Account.manager.PSObject.Properties.Name -Contains 'id')) {
        $AuditLogs.Add([PSCustomObject]@{
                Message = "Requested to lookup manager, but manager.id is missing. This is a scripting issue."
                IsError = $true
            })
        return
    }

    # Check if the manager reference is empty, if so, generate audit message or clear the manager attribute
    if ([string]::IsNullOrEmpty($Account.manager.id)) {
        #As manager.Id is empty, nothing needs to be done here
        Write-Information "Manager Id is empty, clearing manager."
        return
    }

    # manager.Id is available, query manager
    $splatParams = @{
        Headers         = $Headers
        BaseUrl         = $BaseUrl
        PersonReference = $Account.manager.id
    }
    $personManager = Get-TopdeskPersonById @splatParams
        
    if ([string]::IsNullOrEmpty($personManager)) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Manager with reference [$($Account.manager.id)] is not found."
                IsError = $true
            })
    }
    else {
        Write-Output $personManager
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

function Set-TopdeskPersonIsManager {
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
        $isManager
    )

    # Check the current status of the Person and compare it with the status in ArchiveStatus
    if ($isManager -ne $TopdeskPerson.isManager) {

        # Turn on / off isManager
        $body = [PSCustomObject]@{
            isManager = $isManager
        }
        Write-Information "Setting flag isManager to [$isManager] to person with networkLoginName [$($TopdeskPerson.networkLoginName)] and id [$($TopdeskPerson.id)]"
        $splatParams = @{
            Uri     = "$BaseUrl/tas/api/persons/id/$($TopdeskPerson.id)"
            Method  = 'PATCH'
            Headers = $Headers
            Body    = $body | ConvertTo-Json
        }
        $null = Invoke-TopdeskRestMethod @splatParams
    }
}

function Set-TopdeskPerson {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [Object]
        $Account,

        [ValidateNotNullOrEmpty()]
        [Object]
        $TopdeskPerson
    )

    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/persons/id/$($TopdeskPerson.id)"
        Method  = 'PATCH'
        Headers = $Headers
        Body    = $Account | ConvertTo-Json
    }
    $TopdeskPersonUpdated = Invoke-TopdeskRestMethod @splatParams
    return $TopdeskPersonUpdated
}
#endregion functions

#region lookup
try {
    $action = 'Process'

    $account = $actionContext.Data
    # Remove ID field because only used for export data
    if ($account.PSObject.Properties.Name -Contains 'id') {
        $account.PSObject.Properties.Remove('id')
    }

    # Setup authentication headers
    $splatParamsAuthorizationHeaders = @{
        UserName = $actionContext.Configuration.username
        ApiKey   = $actionContext.Configuration.apikey
    }
    $authHeaders = Set-AuthorizationHeaders @splatParamsAuthorizationHeaders
    
    # Resolve branch id
    $splatParamsBranch = @{
        Account = [ref]$account
        Headers = $authHeaders
        BaseUrl = $actionContext.Configuration.baseUrl
    }
    Get-TopdeskBranch @splatParamsBranch

    if ($Account.department.PSObject.Properties.Name -Contains 'name') {
        # Resolve department id
        $splatParamsDepartment = @{
            Account                 = [ref]$account
            Headers                 = $authHeaders
            BaseUrl                 = $actionContext.Configuration.baseUrl
            LookupErrorHrDepartment = $actionContext.Configuration.lookupErrorHrDepartment
            LookupErrorTopdesk      = $actionContext.Configuration.lookupErrorTopdesk
        }
        Get-TopdeskDepartment @splatParamsDepartment  
    }
    else {
        Write-Information "Mapping of [department.name] is missing to lookup the department in Topdesk. Action skipped"
    }

    if ($Account.budgetHolder.PSObject.Properties.Name -Contains 'name') {
        # Resolve budgetholder id
        $splatParamsBudgetHolder = @{
            Account                   = [ref]$account
            Headers                   = $authHeaders
            BaseUrl                   = $actionContext.Configuration.baseUrl
            lookupErrorHrBudgetHolder = $actionContext.Configuration.lookupErrorHrBudgetHolder
            lookupErrorTopdesk        = $actionContext.Configuration.lookupErrorTopdesk
        }
        Get-TopdeskBudgetholder @splatParamsBudgetHolder
    }
    else {
        Write-Information "Mapping of [budgetHolder.name] is missing to lookup the budgetHolder in Topdesk. Action skipped"
    }

    # get person
    $splatParamsPerson = @{
        AccountReference = $actionContext.References.Account
        Headers          = $authHeaders
        BaseUrl          = $actionContext.Configuration.baseUrl
    }
    $TopdeskPerson = Get-TopdeskPerson  @splatParamsPerson

    if ($outputContext.data.manager.PSObject.Properties.Name -Contains 'id') {
        if (-not ([string]::IsNullOrEmpty($actionContext.References.ManagerAccount))) {
            $account | Add-Member @{ manager = [PSCustomObject]@{ id = $actionContext.References.ManagerAccount } } -Force
            # get manager
            $splatParamsManager = @{
                Account = [ref]$account
                Headers = $authHeaders
                BaseUrl = $actionContext.Configuration.baseUrl
            }
            $TopdeskManager = Get-TopdeskPersonManager @splatParamsManager
        }
        elseif (-not ([string]::IsNullOrEmpty($personContext.Manager.ExternalId))) {

            $splatParamsManager = @{
                correlationValue = $personContext.Manager.ExternalId
                correlationField = 'employeeNumber'
                Headers          = $authHeaders
                BaseUrl          = $actionContext.Configuration.baseUrl
                PersonType       = 'manager'
            }
            $TopdeskManager = Get-TopdeskPersonByCorrelationAttribute @splatParamsManager
            # add mref id to manager
            $account | Add-Member @{ manager = [PSCustomObject]@{ id = $TopdeskManager.id } } -Force
        }
    }
    else {
        Write-Information "Mapping of [manager.id] is missing to set the manager. Action skipped"
    }

    if ($outputContext.AuditLogs.isError -contains - $true) {
        throw "Error(s) occured while looking up required values"
    }
    #endregion lookup
    
    #region remove value for update
    if (-not($actionContext.AccountCorrelated -eq $true)) {
        # Example to only set certain attributes when create-correlate. If you don't want to update certain values, you need to remove them here.    
        # $account.PSObject.Properties.Remove('email')
        # $account.PSObject.Properties.Remove('networkLoginName')
        # $account.PSObject.Properties.Remove('tasLoginName')
    }
    #endregion remove value for update

    #region Calulate action
    if (-Not([string]::IsNullOrEmpty($TopdeskPerson))) {
        # Flatten the JSON object
        $accountDifferenceObject = ConvertTo-TopDeskFlatObject -Object $account
        $accountReferenceObject = ConvertTo-TopDeskFlatObject -Object $TopdeskPerson

        # Define properties to compare for update
        $accountPropertiesToCompare = $accountDifferenceObject.PsObject.Properties.Name

        $accountSplatCompareProperties = @{
            ReferenceObject  = $accountReferenceObject.PSObject.Properties | Where-Object { $_.Name -in $accountPropertiesToCompare }
            DifferenceObject = $accountDifferenceObject.PSObject.Properties | Where-Object { $_.Name -in $accountPropertiesToCompare }
        }
        if ($null -ne $accountSplatCompareProperties.ReferenceObject -and $null -ne $accountSplatCompareProperties.DifferenceObject) {
            $accountPropertiesChanged = Compare-Object @accountSplatCompareProperties -PassThru
            $accountOldProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "<=" }
            $accountNewProperties = $accountPropertiesChanged | Where-Object { $_.SideIndicator -eq "=>" }
        }

        if ($accountNewProperties) {
            $action = 'Update'
            Write-Information "Account property(s) required to update: $($accountNewProperties.Name -join ', ')"
        }
        else {
            $action = 'NoChanges'
        }        
    }    
    else {
        $action = 'NotFound' 
    }     

    Write-Information "Compared current account to mapped properties. Result: $action"
    #endregion Calulate action

    #region write
    # Prepare manager record, if manager has to be set
    if (-Not([string]::IsNullOrEmpty($account.manager.id)) -and ($TopdeskManager.isManager -eq $false)) {
        if ($TopdeskManager.status -eq 'personArchived') {

            # Unarchive manager
            $managerShouldArchive = $true
            $splatParamsManagerUnarchive = @{
                TopdeskPerson   = $TopdeskManager
                Headers         = $authHeaders
                BaseUrl         = $actionContext.Configuration.baseUrl
                Archive         = $false
                ArchivingReason = $actionContext.Configuration.personArchivingReason
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                $TopdeskManager.status = Set-TopdeskPersonArchiveStatus @splatParamsManagerUnarchive
            }
            else {
                Write-Warning "DryRun would unarchive manager for update"
            }
        }

        # Set isManager to true
        $splatParamsManagerIsManager = @{
            TopdeskPerson = $TopdeskManager
            Headers       = $authHeaders
            BaseUrl       = $actionContext.Configuration.baseUrl
            IsManager     = $true
        }

        if (-Not($actionContext.DryRun -eq $true)) {
            Set-TopdeskPersonIsManager @splatParamsManagerIsManager
        }
        else {
            Write-Warning "DryRun would set isManager to [$($splatParamsManagerIsManager.IsManager)]"
        }

        # Archive manager if required
        if ($managerShouldArchive) {

            # Archive manager
            $splatParamsManagerArchive = @{
                TopdeskPerson   = $TopdeskManager
                Headers         = $authHeaders
                BaseUrl         = $actionContext.Configuration.baseUrl
                Archive         = $true
                ArchivingReason = $actionContext.Configuration.personArchivingReason
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                $TopdeskManager.status = Set-TopdeskPersonArchiveStatus @splatParamsManagerArchive
            }
            else {
                Write-Warning "DryRun would re-archive manager"
            }
        }
    }

    switch ($action) {
        'Update' {
            # Unarchive person if required
            if ($TopdeskPerson.status -eq 'personArchived') {
        
                # Unarchive person
                $personShouldArchive = $true
                $splatParamsPersonUnarchive = @{
                    TopdeskPerson   = $TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $actionContext.Configuration.baseUrl
                    Archive         = $false
                    ArchivingReason = $actionContext.Configuration.personArchivingReason
                }

                if (-Not($actionContext.DryRun -eq $true)) {
                    $null = Set-TopdeskPersonArchiveStatus @splatParamsPersonUnarchive
                }
                else {
                    Write-Warning "DryRun would unarchive person for update"
                }
            }
        
            # Update TOPdesk person
            Write-Information "Updating Topdesk person for: [$($personContext.Person.DisplayName)]"
                        
            $splatParamsPersonUpdate = @{
                TopdeskPerson = $TopdeskPerson
                Account       = $account
                Headers       = $authHeaders
                BaseUrl       = $actionContext.Configuration.baseUrl
            }

            if (-Not($actionContext.DryRun -eq $true)) {
                $TopdeskPersonUpdated = Set-TopdeskPerson @splatParamsPersonUpdate
            }
            else {
                Write-Warning "DryRun would update Person."
            }
            
            # As the update process could be started for an inactive HelloID person, the user return should be archived state
            if ($personShouldArchive) {
            
                # Archive person
                $splatParamsPersonArchive = @{
                    TopdeskPerson   = $TopdeskPerson
                    Headers         = $authHeaders
                    BaseUrl         = $actionContext.Configuration.baseUrl
                    Archive         = $true
                    ArchivingReason = $actionContext.Configuration.personArchivingReason
                }
                if (-Not($actionContext.DryRun -eq $true)) {
                    $TopdeskPersonUpdated.status = Set-TopdeskPersonArchiveStatus @splatParamsPersonArchive
                }
                else {
                    Write-Warning "DryRun would re-archive person after update"
                }
            }
                
            $outputContext.AccountReference = $TopdeskPerson.id
            $outputContext.Data = $TopdeskPersonUpdated
            $outputContext.PreviousData = $TopdeskPerson

            if (-Not($actionContext.DryRun -eq $true)) {
                Write-Information "Account with id [$($TopdeskPerson.id)] and dynamicName [($($TopdeskPersonUpdated.dynamicName))] successfully updated."

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Account with id [$($TopdeskPerson.id)] and dynamicName [($($TopdeskPersonUpdated.dynamicName))] successfully updated."
                        IsError = $false
                    })
            }

            break
        }
        
        'NoChanges' {        
            $outputContext.AccountReference = $TopdeskPerson.id
            $outputContext.Data = $TopdeskPerson
            $outputContext.PreviousData = $TopdeskPerson

            Write-Information "Account with id [$($TopdeskPerson.id)] and dynamicName [($($TopdeskPerson.dynamicName))]successfully checked. No changes required"

            # AuditLog is skipped because $outputContext.Data & $outputContext.PreviousData are the same. If auditlog is required please change this variables above
            # $outputContext.AuditLogs.Add([PSCustomObject]@{
            #         Message = "Account with id [$($TopdeskPerson.id)] and dynamicName [($($TopdeskPerson.dynamicName))] successfully checked. No changes required"
            #         IsError = $false
            #     })

            break
        }

        'NotFound' {                
            Write-Information "Account with id [$($actionContext.References.Account)] is not found. If the person is deleted, you might need to regrant the entitlement."

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Account with id [$($actionContext.References.Account)] is not found. If the person is deleted, you might need to regrant the entitlement."
                    IsError = $true
                })

            break
        }
    }
    #endregion Write
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
}
