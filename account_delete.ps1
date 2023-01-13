#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Delete
#
# Version: 2.0
#####################################################

# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()
$aRef = $AccountReference | ConvertFrom-Json

# Set debug logging
switch ($($config.IsDebug)) {
    $true  { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region mapping
# Clear email, networkLoginName & tasLoginName, if you need to clear other values, add these here
$account = [PSCustomObject]@{
    email               = $null
    networkLoginName    = $null
    tasLoginName        = ''
}
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
                $splatParams['Body'] = [Text.Encoding]::UTF8.GetBytes($Body)
            }
            Invoke-RestMethod @splatParams -Verbose:$false
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
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

    # Output result if something was found. Result is empty when nothing is found (i think) - TODO: Test this!!!
    Write-Output $responseGet
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
        Uri     = "$BaseUrl/tas/api/persons/id/$($TopdeskPerson.id)"
        Method  = 'PATCH'
        Headers = $Headers
        Body    = $Account | ConvertTo-Json
    }
    $null = Invoke-TopdeskRestMethod @splatParams
}
#endregion helperfunctions

try {
    $action = 'Process'

    # Setup authentication headers
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apiKey

    $splatParams = @{
        Headers                   = $authHeaders
        BaseUrl                   = $config.baseUrl
        PersonReference           = $aRef
    }
    $TopdeskPerson = Get-TopdeskPersonById @splatParams

    if ([string]::IsNullOrEmpty($TopdeskPerson)) {

        # When a person cannot be found, assume the person is already deleted and report success with the default audit message
        if ($dryRun -eq $true) {
            $auditLogs.Add([PSCustomObject]@{
                Message = "Archiving TOPdesk person for: [$($p.DisplayName)]: person with account reference [$aRef] cannot be found"
            })
        }
    } else {

        # Add an auditMessage showing what will happen during enforcement
        if ($dryRun -eq $true) {
            $auditLogs.Add([PSCustomObject]@{
                Message = "Archiving TOPdesk person for: [$($p.DisplayName)], will be executed during enforcement"
            })
        } else {
            Write-Verbose "Archiving TOPdesk person"

            # Unarchive person if required
            if ($TopdeskPerson.status -eq 'personArchived') {

                # Unarchive person
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

            # Update TOPdesk person
            $splatParamsPersonUpdate = @{
                TopdeskPerson   = $TopdeskPerson
                Account         = $account
                Headers         = $authHeaders
                BaseUrl         = $config.baseUrl
            }
            Set-TopdeskPerson @splatParamsPersonUpdate

            # Always archive person in the delete process
            if ($TopdeskPerson.status -ne 'personArchived') {

                # Archive person
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

            $success = $true
            $auditLogs.Add([PSCustomObject]@{
                Message = "Archive person was successful."
                IsError = $false
            })
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    Write-Verbose ($ex | ConvertTo-Json)
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            $errorMessage = "Could not $action person. Error: $($ex.ErrorDetails.Message)"
        } else {
            #$errorObj = Resolve-HTTPError -ErrorObject $ex
            $errorMessage = "Could not $action person. Error: $($ex.Exception.Message)"
        }
    } else {
        $errorMessage = "Could not archive person. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }

    $auditLogs.Add([PSCustomObject]@{
        Message = $errorMessage
        IsError = $true
    })
} finally {
    $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
