#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Create
#
# Version: 1.0.0
#####################################################

# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$mRef = $managerAccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Set debug logging
switch ($($config.IsDebug)) {
    $true  { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region mapping
# Last name generation based on name convention code
#  B  "<birth name prefix> <birth name>"
#  P  "<partner name prefix> <partner name>"
#  BP "<birth name prefix> <birth name> - <partner name prefix> <partner name>"
#  PB "<partner name prefix> <partner name> - <birth name prefix> <birth name>"
function New-TopdeskSurname {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]
        $person
    )

    if([string]::IsNullOrEmpty($person.Name.FamilyNamePrefix)) {
        $prefix = ""
    } else {
        $prefix = $person.Name.FamilyNamePrefix + " "
    }

    if([string]::IsNullOrEmpty($person.Name.FamilyNamePartnerPrefix)) {
        $partnerPrefix = ""
    } else {
        $partnerPrefix = $person.Name.FamilyNamePartnerPrefix + " "
    }

    $TopdeskSurname = switch($person.Name.Convention) {
                    "B"  { $prefix + $person.Name.FamilyName }
                    "BP" { $prefix + $person.Name.FamilyName + " - " + $partnerprefix + $person.Name.FamilyNamePartner }
                    "P"  { $partnerPrefix + $person.Name.FamilyNamePartner }
                    "PB" { $partnerPrefix + $person.Name.FamilyNamePartner + " - " + $prefix + $person.Name.FamilyName }
                    default { $prefix + $person.Name.FamilyName }
    }
    Write-Output $TopdeskSurname
}

function New-TopdeskGender {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [object]
        $person
    )

    $gender = switch($person.details.Gender) {
        "M" { "MALE"}
        "V" { "FEMALE"}
        default { 'UNDEFINED'}
    }

    Write-Output $gender
}

# Account mapping. See for all possible options the Topdesk 'supporting files' API documentation at
# https://developers.topdesk.com/explorer/?page=supporting-files#/Persons/createPerson
$account = [PSCustomObject]@{
    surName             = New-TopdeskSurname -Person $p        # Generate surname according to the naming convention code.
    firstName           = $p.Name.NickName
    firstInitials       = $p.Name.Initials
    gennder             = New-TopdeskGender  -Person $p
    email               = $p.Accounts.MicrosoftActiveDirectory.mail
    employeeNumber      = $p.ExternalId
    networkLoginName    = $p.Accounts.MicrosoftActiveDirectory.SamAccountName
    tasLoginName        = $p.Accounts.MicrosoftActiveDirectory.SamAccountName
    jobTitle            = $p.PrimaryContract.Title.Name
    branch              = @{ lookupValue = 'Fixed branch' } #$p.PrimaryContract.Location.Name
    department          = @{ lookupValue = $p.PrimaryContract.Department.DisplayName }
    budgetholder        = @{ lookupValue = $p.PrimaryContract.CostCenter.Name }
    isManager           = $false
    manager             = @{ id = $mRef }
    showDepartment      = $true
}

#correlation attribute. Is used to lookup the user in the Get-TopdeskPerson function. Not migrated to settings because it's only used in the user create script.
$correlationAttribute = 'employeeNumber'
#endregion mapping

#region helperfunctions
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
            ### As branch is a required field, if no branch is found, an error is logged
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

function Get-TopdesDepartment {
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
        #[Bool]
        $LookupErrorHrDepartment,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        #[Bool]
        $LookupErrorTopdesk,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        [ref]$Account,

        #[Parameter(Mandatory)]
        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if department.lookupValue property exists in the account object set in the mapping
    if (-not($account.department.Keys -Contains 'lookupValue')) {
        $errorMessage = "Requested to lookup department, but department.lookupValue is not set. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # When department.lookupValue is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($account.department.lookupValue)) {
        if ([System.Convert]::ToBoolean($LookupErrorHrDepartment)) {
            # True, no department in lookup value = throw error
            $errorMessage = "The lookup value for Department is empty and the connector is configured to stop when this happens."
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        } else {
            # False, no department in lookup value = clear value
            Write-Verbose "Clearing department. (lookupErrorHrdDepartment = False)"
            $account.department.PSObject.Properties.Remove('lookupValue')
            $account.department | Add-Member -NotePropertyName id -NotePropertyValue $null
        }
    } else {
        # Lookup Value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/departments"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-TopdeskRestMethod @splatParams
        $department = $responseGet | Where-object name -eq $account.department.lookupValue

        # When department is not found in Topdesk
        if ([string]::IsNullOrEmpty($department.id)) {
            if ([System.Convert]::ToBoolean($LookupErrorTopdesk)) {
                ### True, no department found = throw error
                $errorMessage = "Department [$($account.department.lookupValue)] not found in Topdesk and the connector is configured to stop when this happens."
                $auditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
            } else {
                ### False, no department found = remove department field (leave empty on creation or keep current value on update)
                $account.PSObject.Properties.Remove('department')
                Write-Verbose "Not overwriting or setting department as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        } else {
            # Department is found in Topdesk, set in Topdesk
            $account.department.PSObject.Properties.Remove('lookupValue')
            $account.department | Add-Member -NotePropertyName id -NotePropertyValue $department.id
        }
    }
}

function Get-TopdeskBudgetHolder {
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
        #[Bool]
        $LookupErrorHrBudgetHolder,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        #[Bool]
        $LookupErrorTopdesk,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        [ref]$Account,

        #[Parameter(Mandatory)]
        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if budgetholder.lookupValue property exists in the account object set in the mapping
    if (-not($account.budgetholder.Keys -Contains 'lookupValue')) {
        $errorMessage = "Requested to lookup Budgetholder, but budgetholder.lookupValue is missing. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # When budgetholder.lookupValue is null or empty (it is empty in the source or it's a mapping error)
    if ([string]::IsNullOrEmpty($account.budgetholder.lookupValue)) {
        if ([System.Convert]::ToBoolean($lookupErrorHrBudgetHolder)) {
            # True, no budgetholder in lookup value = throw error
            $errorMessage = "The lookup value for Budgetholder is empty and the connector is configured to stop when this happens."
            $auditLogs.Add([PSCustomObject]@{
                Message = $errorMessage
                IsError = $true
            })
        } else {
            # False, no budgetholder in lookup value = clear value
            $account.budgetHolder.PSObject.Properties.Remove('lookupValue')
            $account.budgetHolder | Add-Member -NotePropertyName id -NotePropertyValue $null
            Write-Verbose "Clearing budgetholder. (lookupErrorHrBudgetHolder = False)"
        }
    } else {
        # Lookup Value is filled in, lookup value in Topdesk
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/budgetholders"
            Method  = 'GET'
            Headers = $Headers
        }
        $responseGet = Invoke-TopdeskRestMethod @splatParams
        $budgetHolder = $responseGet | Where-object name -eq $account.budgetHolder.lookupValue

        # When budgetholder is not found in Topdesk
        if ([string]::IsNullOrEmpty($budgetHolder.id)) {
            if ([System.Convert]::ToBoolean($lookupErrorTopdesk)) {
                # True, no budgetholder found = throw error
                $errorMessage = "Budgetholder [$($account.budgetHolder.lookupValue)] not found in Topdesk and the connector is configured to stop when this happens."
                $auditLogs.Add([PSCustomObject]@{
                    Message = $errorMessage
                    IsError = $true
                })
            } else {
                # False, no budgetholder found = remove budgetholder field (leave empty on creation or keep current value on update)
                $account.PSObject.Properties.Remove('budgetHolder')
                Write-Verbose "Not overwriting or setting Budgetholder as it can't be found in Topdesk. (lookupErrorTopdesk = False)"
            }
        } else {
            # Budgetholder is found in Topdesk, set in Topdesk
            $account.budgetHolder.PSObject.Properties.Remove('lookupValue')
            $account.budgetHolder | Add-Member -NotePropertyName id -NotePropertyValue $budgetHolder.id
        }
    }
}

function Get-TopdeskPersonByCorrelationAttribute {
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

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]
        $CorrelationAttribute,

        #[Parameter(Mandatory)]
        [System.Collections.Generic.List[PSCustomObject]]
        [ref]$AuditLogs
    )

    # Check if the correlation attribute exists in the account object set in the mapping
    if (-not([bool]$account.PSObject.Properties[$CorrelationAttribute])) {
        $errorMessage = "The correlation attribute [$CorrelationAttribute] is  missing in the account mapping. This is a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Check if the correlationAttribute is not empty
    if ([string]::IsNullOrEmpty($account.$CorrelationAttribute)) {
        $errorMessage = "The correlation attribute [$CorrelationAttribute] is empty. This is likely a scripting issue."
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
        return
    }

    # Lookup value is filled in, lookup value in Topdesk
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/persons?page_size=2&query=$($correlationAttribute)=='$($account.$CorrelationAttribute)'"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams

    # Check if only one result is returned
    if ([string]::IsNullOrEmpty($responseGet)) {
        # no results found
        Write-Output $null
    } elseif ($responseGet.Count -eq 1) {
        # one record found, correlate, return user
        write-output $responseGet
    } else {
        # Multiple records found, correlation
        $errorMessage = "Multiple [$($responseGet.Count)] persons found with [$CorrelationAttribute] [$($account.$CorrelationAttribute)]. Login names: [$($responseGet.tasLoginName)]"
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
        Uri     = "$baseUrl/tas/api/persons/id/$PersonReference"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams
    # Output result if something was found. Result is empty when nothing is found (i think) - TODO: Test this!!!
    Write-Output $responseGet
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

function Set-TopdeskPersonIsManager {
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
        $isManager
    )
    # Check the current status of the Person and compare it with the status in ArchiveStatus
    if ($isManager -ne $TopdeskPerson.isManager) {

        # Turn of / off manager
        $body = [PSCustomObject]@{
            isManager = $isManager
        }
        Write-Verbose "Set isManager to [$isManager] to person with id [$($TopdeskPerson.id)]"
        $splatParams = @{
            Uri     = "$baseUrl/tas/api/person/$($TopdeskPerson.id)"
            Method  = 'PATCH'
            Headers = $Headers
            Body    = $body
        }
        $null = Invoke-TopdeskRestMethod @splatParams
        $TopdeskPerson.status = $isManager
    }
}


function Set-TopdeskPerson {
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

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [Object]
        $TopdeskPerson
    )

    Write-Verbose "Updating person"
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/person/$($TopdeskPerson.id)"
        Method  = 'PATCH'
        Headers = $Headers
        Body    = $Account | ConvertTo-Json
    }
    $null = Invoke-TopdeskRestMethod @splatParams
}

function New-TopdeskPerson {
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
        $Account
    )

    Write-Verbose "Creating person"
    $splatParams = @{
        Uri     = "$baseUrl/tas/api/person"
        Method  = 'POST'
        Headers = $Headers
        Body    = $Account | ConvertTo-Json
    }
    $null = Invoke-TopdeskRestMethod @splatParams
}

#endregion helperfunctions

#region lookup
try {
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

    # Resolve department id
    $splatParamsDepartment = @{
        Account                   = [ref]$account
        AuditLogs                 = [ref]$auditLogs
        Headers                   = $authHeaders
        baseUrl                   = $config.baseUrl
        lookupErrorHrDepartment   = $config.lookupErrorHrDepartment
        lookupErrorTopdesk        = $config.lookupErrorTopdesk
    }
    Get-TopdesDepartment @splatParamsDepartment

    # Resolve budgetholder id
    $splatParamsBudgetholder = @{
        Account                   = [ref]$account
        AuditLogs                 = [ref]$auditLogs
        Headers                   = $authHeaders
        baseUrl                   = $config.baseUrl
        lookupErrorHrBudgetholder = $config.lookupErrorHrBudgetholder
        lookupErrorTopdesk        = $config.lookupErrorTopdesk
    }
    Get-TopdeskBudgetholder @splatParamsBudgetholder

    # get person
    $splatParamsPerson = @{
        Account                   = $account
        AuditLogs                 = [ref]$auditLogs
        CorrelationAttribute      = $correlationAttribute
        Headers                   = $authHeaders
        baseUrl                   = $config.baseUrl
    }
    $TopdeskPerson = Get-TopdeskPersonByCorrelationAttribute @splatParamsPerson

    # get manager
    $splatParamsManager = @{
        Account                   = [ref]$account
        AuditLogs                 = [ref]$auditLogs
        Headers                   = $authHeaders
        baseUrl                   = $config.baseUrl
    }
    $TopdeskManager = Get-TopdeskPersonManager @splatParamsManager

    if ($auditLogs.isError -contains -$true) {
        Throw "Errors occured while looking up required values"
    }
#endregion lookup

# region write
    # Prepare manager record, if manager has to be set
    if (-Not([string]::IsNullOrEmpty($account.manager.id))) {
        if ($TopdeskManager.isManager -eq $false) {
            if ($TopdeskManager.status -eq 'personArchived') {

                # Unarchive person
                $shouldArchive  = $true
                $splatParamsManagerUnarchive = @{
                    TopdeskPerson   = [ref]$TopdeskManager
                    Headers         = $authHeaders
                    BaseUrl         = $config.baseUrl
                    Archive         = $false
                }
                Set-TopdeskPersonArchiveStatus @splatParamsManagerUnarchive
            }

            # Set isManager to true
            $splatParamsManagerIsManager = @{
                TopdeskPerson   = [ref]$TopdeskManager
                Headers         = $authHeaders
                BaseUrl         = $config.baseUrl
                IsManager       = $true
            }
            Set-TopdeskPersonIsManager @splatParamsManagerIsManager

            # Archive manager if required
            if ($shouldArchive -and $TopdeskManager.status -ne 'personArchived') {
                # Archive person
                $splatParamsManagerArchive = @{
                    TopdeskPerson   = [ref]$TopdeskManager
                    Headers         = $authHeaders
                    BaseUrl         = $config.baseUrl
                    Archive         = $true
                }
                Set-TopdeskPersonArchiveStatus @splatParamsManagerArchive
            }
        }
    }

    # Verify if a user must be created or correlated
    if ([string]::IsNullOrEmpty($TopdeskPerson)) {
        $action = 'Create'
    } else {
        $action = 'Correlate'
        # example to only set certain attributes when creating a person, but skip them when updating
        # $Account.PSObject.Properties.Remove('showDepartment')
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
            Message = "$action Topdesk account for: [$($p.DisplayName)], will be executed during enforcement"
        })
    }

    # Process
    if (-not($dryRun -eq $true)){
        switch ($action) {
            'Create' {
                Write-Verbose "Creating Topdesk person for: [$($p.DisplayName)]"
                $splatParamsPersonUnarchive = @{
                    Account         = $account
                    Headers         = $authHeaders
                    BaseUrl         = $config.baseUrl
                }
                New-TopdeskPerson @splatParamsPersonUnarchive

            } 'Correlate'{
                Write-Verbose "Correlating and updating Topdesk person for: [$($p.DisplayName)]"

                # Unarchive person if required
                if ($TopdeskPerson.status -eq 'personArchived') {

                    # Unarchive person
                    $splatParamsPersonUnarchive = @{
                        TopdeskPerson   = [ref]$TopdeskPerson
                        Headers         = $authHeaders
                        BaseUrl         = $config.baseUrl
                        Archive         = $false
                    }
                    Set-TopdeskPersonArchiveStatus @splatParamsPersonUnarchive
                }

                # Update TOPdesk person
                $splatParamsPersonUnarchive = @{
                    TopdeskPerson   = $TopdeskPerson
                    Account         = $account
                    Headers         = $authHeaders
                    BaseUrl         = $config.baseUrl
                }
                Set-TopdeskPerson @splatParamsPersonUnarchive
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
            Message = "$action account for: [$($p.DisplayName)] was successful."
            IsError = $false
        })
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorMessage = "Could not create person. Error: $($ex.ErrorDetails.Message)"
    } else {
        $errorMessage = "Could not create person. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }

    # Only log when there are no lookup values, as these generate their own audit message
    if (-Not($ex.Exception.Message -eq 'Errors occured while looking up required values')) {
        $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
    }
# End
} finally {
   $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}