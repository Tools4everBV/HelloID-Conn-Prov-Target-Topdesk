#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Create
#
# Version: 3.0.0 | Powershell V2
#####################################################

# Set to true at start, because only when an error occurs it is set to false
$outputContext.Success = $true

# AccountReference must have a value for dryRun
$outputContext.AccountReference = "Unknown"

# Set debug logging
switch ($($actionContext.Configuration.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-HTTPError {
    param (
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
        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }
        Write-Output $httpErrorObj
    }
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
    $authHeaders.Add("Accept", 'application/json')

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
            Throw $_
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

    # Check if branch.lookupValue property exists in the account object set in the mapping
    if (-not($account.branch.PSObject.Properties.Name -contains 'lookupValue')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Requested to lookup branch, but branch.lookupValue is missing. This is a mapping issue."
                IsError = $true
            })
        return
    }
        
    if ([string]::IsNullOrEmpty($Account.branch.lookupValue)) {
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
        $branch = $responseGet | Where-object name -eq $Account.branch.lookupValue
        # When branch is not found in Topdesk
        if ([string]::IsNullOrEmpty($branch.id)) {

            # As branch is a required field, if no branch is found, an error is logged
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Branch with name [$($Account.branch.lookupValue)] isn't found in Topdesk but it's a required field."
                    IsError = $true
                })
        }
        else {
            # Branch is found in Topdesk, set in Topdesk
            $Account.branch.PSObject.Properties.Remove('lookupValue')
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

    # Check if department.lookupValue property exists in the account object set in the mapping
    if (-not($Account.department.PSObject.Properties.Name -Contains 'lookupValue')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Requested to lookup department, but department.lookupValue is not set. This is a mapping issue."
                IsError = $true
            })
        return
    }
    # When department.lookupValue is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($Account.department.lookupValue)) {
        if ([System.Convert]::ToBoolean($LookupErrorHrDepartment)) {
            # True, no department in lookup value = throw error
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "The lookup value for Department is empty and the connector is configured to stop when this happens."
                    IsError = $true
                })
        }
        else {
            # False, no department in lookup value = clear value
            Write-Verbose "Clearing department. (lookupErrorHrDepartment = False)"
            $Account.department.PSObject.Properties.Remove('lookupValue')
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
        $department = $responseGet | Where-object name -eq $Account.department.lookupValue

        # When department is not found in Topdesk
        if ([string]::IsNullOrEmpty($department.id)) {
            if ([System.Convert]::ToBoolean($LookupErrorTopdesk)) {
                # True, no department found = throw error
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Department [$($Account.department.lookupValue)] not found in Topdesk and the connector is configured to stop when this happens."
                        IsError = $true
                    })
            }
            else {
                # False, no department found = remove department field (leave empty on creation or keep current value on update)
                $Account.department.PSObject.Properties.Remove('lookupValue')
                $Account.PSObject.Properties.Remove('department')
                Write-Verbose "Not overwriting or setting department as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        }
        else {
            # Department is found in Topdesk, set in Topdesk
            $Account.department.PSObject.Properties.Remove('lookupValue')
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

    # Check if budgetholder.lookupValue property exists in the account object set in the mapping
    if (-not($Account.budgetHolder.PSObject.Properties.Name -Contains 'lookupValue')) {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Requested to lookup budgetholder, but budgetholder.lookupValue is missing. This is a mapping issue."
                IsError = $true
            })
        return
    }

    # When budgetholder.lookupValue is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($Account.budgetHolder.lookupValue)) {
        if ([System.Convert]::ToBoolean($lookupErrorHrBudgetHolder)) {
            # True, no budgetholder in lookup value = throw error
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "The lookup value for budgetholder is empty and the connector is configured to stop when this happens."
                    IsError = $true
                })
        }
        else {
            # False, no budgetholder in lookup value = clear value
            Write-Verbose "Clearing budgetholder. (lookupErrorHrBudgetHolder = False)"
            $Account.budgetHolder.PSObject.Properties.Remove('lookupValue')
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
        $budgetHolder = $responseGet | Where-object name -eq $Account.budgetHolder.lookupValue

        # When budgetholder is not found in Topdesk
        if ([string]::IsNullOrEmpty($budgetHolder.id)) {
            if ([System.Convert]::ToBoolean($lookupErrorTopdesk)) {
                # True, no budgetholder found = throw error
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Budgetholder [$($Account.budgetHolder.lookupValue)] not found in Topdesk and the connector is configured to stop when this happens."
                        IsError = $true
                    })
            }
            else {
                # False, no budgetholder found = remove budgetholder field (leave empty on creation or keep current value on update)
                $Account.budgetHolder.PSObject.Properties.Remove('lookupValue')
                $Account.PSObject.Properties.Remove('budgetHolder')
                Write-Verbose "Not overwriting or setting budgetholder as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        }
        else {
            # Budgetholder is found in Topdesk, set in Topdesk
            $Account.budgetHolder.PSObject.Properties.Remove('lookupValue')
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
                Message = "Multiple [$($responseGet.Count)] $($PersonType)s found with [$CorrelationAttribute] [$($CorrelationValue)]. Login names: [$($responseGet.tasLoginName -join ', ')]"
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

    # Output result if something was found. Result is empty when nothing is found (i think) - TODO: Test this!!!
    Write-Output $responseGet
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
        Write-Verbose "Manager Id is empty, clearing manager."
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
        [Ref]$TopdeskPerson,

        [ValidateNotNullOrEmpty()]
        [Bool]
        $Archive,

        [Parameter()]
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
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Archiving reason [$ArchivingReason] not found in Topdesk"
                    IsError = $true
                })
            Throw "Error(s) occured while looking up required values"
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
        Write-Verbose "Setting flag isManager to [$isManager] to person with networkLoginName [$($TopdeskPerson.networkLoginName)] and id [$($TopdeskPerson.id)]"
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

    Write-Verbose "Updating person"
    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/persons/id/$($TopdeskPerson.id)"
        Method  = 'PATCH'
        Headers = $Headers
        Body    = $Account | ConvertTo-Json
    }
    $null = Invoke-TopdeskRestMethod @splatParams
}

function New-TopdeskPerson {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers,

        [ValidateNotNullOrEmpty()]
        [Object]
        $Account
    )

    Write-Verbose "Creating person"

    # Clear manager attribute when id = null
    if ([string]::IsNullOrEmpty($Account.manager.id)) {
        $Account.manager.PSObject.Properties.Remove('id')
        $Account.PSObject.Properties.Remove('manager')
    }

    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/persons"
        Method  = 'POST'
        Headers = $Headers
        Body    = $Account | ConvertTo-Json
    }
    $TopdeskPerson = Invoke-TopdeskRestMethod @splatParams
    Write-Output $TopdeskPerson
}
#endregion functions

#region lookup
try {
    $action = 'Process'
    
    # Setup authentication headers
    $splatParamsAuthorizationHeaders = @{
        UserName = $actionContext.Configuration.username
        ApiKey   = $actionContext.Configuration.apikey
    }
    $authHeaders = Set-AuthorizationHeaders @splatParamsAuthorizationHeaders

    # Check if we should try to correlate the account
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.accountField
        $correlationValue = $actionContext.CorrelationConfiguration.accountFieldValue

        if ([string]::IsNullOrEmpty($correlationField)) {
            Write-Warning "Correlation is enabled but not configured correctly."
            Throw "Correlation is enabled but not configured correctly."
        }

        if ([string]::IsNullOrEmpty($correlationValue)) {
            Write-Warning "The correlation value for [$correlationField] is empty. This is likely a scripting issue."
            Throw "The correlation value for [$correlationField] is empty. This is likely a scripting issue."
        }

        # get person
        $splatParamsPerson = @{
            correlationValue = $correlationValue
            correlationField = $correlationField
            Headers          = $authHeaders
            BaseUrl          = $actionContext.Configuration.baseUrl
            PersonType       = 'person'
        }
        $TopdeskPerson = Get-TopdeskPersonByCorrelationAttribute @splatParamsPerson

        if (!([string]::IsNullOrEmpty($TopdeskPerson))) {
            if (-Not($actionContext.DryRun -eq $true)) {
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "CorrelateAccount" # Optionally specify a different action for this audit log
                        Message = "Correlated account with username $($correlatedAccount.UserName) on field $($correlationField) with value $($correlationValue)"
                        IsError = $false
                    })


            }
            else {
                Write-Warning "DryRun: Would correlate account [$($personContext.Person.DisplayName)] on field [$($correlationField)] with value [$($correlationValue)]"
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "DryRun: Would correlate account [$($personContext.Person.DisplayName)] on field [$($correlationField)] with value [$($correlationValue)]"
                    })
            }
            $outputContext.AccountReference = $TopdeskPerson.id
            $outputContext.AccountCorrelated = $true
        }
    }
    else {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
                Message = "Configuration of correlation is madatory."
                IsError = $true
            })
        Throw "Configuration of correlation is madatory."
    }

    if (!$outputContext.AccountCorrelated) {     
        $account = $actionContext.Data
        # Remove ID field because only used for export data
        if ($account.PSObject.Properties.Name -Contains 'id') {
            $account.PSObject.Properties.Remove('id')
        }

        # Resolve branch id
        $splatParamsBranch = @{
            Account = [ref]$account
            Headers = $authHeaders
            BaseUrl = $actionContext.Configuration.baseUrl
        }
        Get-TopdeskBranch @splatParamsBranch

        # Resolve department id
        $splatParamsDepartment = @{
            Account                 = [ref]$account
            Headers                 = $authHeaders
            BaseUrl                 = $actionContext.Configuration.baseUrl
            LookupErrorHrDepartment = $actionContext.Configuration.lookupErrorHrDepartment
            LookupErrorTopdesk      = $actionContext.Configuration.lookupErrorTopdesk
        }
        Get-TopdeskDepartment @splatParamsDepartment  

        # Resolve budgetholder id
        $splatParamsBudgetHolder = @{
            Account                   = [ref]$account
            Headers                   = $authHeaders
            BaseUrl                   = $actionContext.Configuration.baseUrl
            lookupErrorHrBudgetHolder = $actionContext.Configuration.lookupErrorHrBudgetHolder
            lookupErrorTopdesk        = $actionContext.Configuration.lookupErrorTopdesk
        }
        Get-TopdeskBudgetholder @splatParamsBudgetHolder

        if (-not ([string]::IsNullOrEmpty($actionContext.References.ManagerAccount))) {
            $account.manager.id = $actionContext.References.ManagerAccount
            # get manager
            $splatParamsManager = @{
                Account = [ref]$account
                Headers = $authHeaders
                BaseUrl = $actionContext.Configuration.baseUrl
            }
            $TopdeskManager = Get-TopdeskPersonManager @splatParamsManager


        }
        elseif (($Account.manager.PSObject.Properties.Name -Contains 'id') -and (-not ([string]::IsNullOrEmpty($personContext.Manager.ExternalId)))) {
    
            $splatParamsManager = @{
                correlationValue = $personContext.Manager.ExternalId
                correlationField = 'employeeNumber'
                Headers          = $authHeaders
                BaseUrl          = $actionContext.Configuration.baseUrl
                PersonType       = 'manager'
            }
            $TopdeskManager = Get-TopdeskPersonByCorrelationAttribute @splatParamsManager
            # add mref id to manager
            $account.manager.id = $TopdeskManager.id


        }

        if ($outputContext.AuditLogs.isError -contains $true) {
            Throw "Error(s) occured while looking up required values"
        }
        #endregion lookup

        #region write
        $action = 'Create'
        if (-Not($actionContext.DryRun -eq $true)) {
            # Prepare manager record, if manager has to be set
            if (-Not([string]::IsNullOrEmpty($account.manager.id)) -and ($TopdeskManager.isManager -eq $false)) {
                if ($TopdeskManager.status -eq 'personArchived') {

                    # Unarchive manager
                    $managerShouldArchive = $true
                    $splatParamsManagerUnarchive = @{
                        TopdeskPerson   = [ref]$TopdeskManager
                        Headers         = $authHeaders
                        BaseUrl         = $actionContext.Configuration.baseUrl
                        Archive         = $false
                        ArchivingReason = $actionContext.Configuration.personArchivingReason
                    }
                    Set-TopdeskPersonArchiveStatus @splatParamsManagerUnarchive
                }

                # Set isManager to true
                $splatParamsManagerIsManager = @{
                    TopdeskPerson = $TopdeskManager
                    Headers       = $authHeaders
                    BaseUrl       = $actionContext.Configuration.baseUrl
                    IsManager     = $true
                }
                Set-TopdeskPersonIsManager @splatParamsManagerIsManager

                # Archive manager if required
                if ($managerShouldArchive -and $TopdeskManager.status -ne 'personArchived') {

                    # Archive manager
                    $splatParamsManagerArchive = @{
                        TopdeskPerson   = [ref]$TopdeskManager
                        Headers         = $authHeaders
                        BaseUrl         = $actionContext.Configuration.baseUrl
                        Archive         = $true
                        ArchivingReason = $actionContext.Configuration.personArchivingReason
                    }
                    Set-TopdeskPersonArchiveStatus @splatParamsManagerArchive
                }
            }
            Write-Verbose "Creating Topdesk person for: [$($personContext.Person.DisplayName)]"
            $splatParamsPersonNew = @{
                Account = $account
                Headers = $authHeaders
                BaseUrl = $actionContext.Configuration.baseUrl
            }
            $TopdeskPerson = New-TopdeskPerson @splatParamsPersonNew
            $outputContext.AccountReference = $TopdeskPerson.id
            $outputContext.Data = $TopdeskPerson

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Action  = "CreateAccount" # Optionally specify a different action for this audit log
                    Message = "Account with id [$($TopdeskPerson.id)] successfully created"
                    IsError = $false
                })
        }
        else {
            Write-Warning "DryRun: Would create account [$($personContext.Person.DisplayName)]"
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "DryRun: Would create account [$($personContext.Person.DisplayName)]"
                })
        }
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        #write-verbose ($ex | ConvertTo-Json)

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            $errorMessage = "Could not $action person. Error: $($ex.ErrorDetails.Message)"
        }
        else {
            #$errorObj = Resolve-HTTPError -ErrorObject $ex
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
    # Check if auditLogs contains errors, if errors are found, set success to false
    if ($outputContext.AuditLogs.IsError -contains $true) {
        $outputContext.Success = $false
    }
}
#endregion Write