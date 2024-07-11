#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Enable
# PowerShell V2
#####################################################

# Set debug logging
switch ($($actionContext.Configuration.isDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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
            Throw $_
        }
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

        # Throw an error when account reference is empty
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

    # get person
    $splatParamsPerson = @{
        AccountReference = $actionContext.References.Account
        Headers          = $authHeaders
        BaseUrl          = $actionContext.Configuration.baseUrl
    }
    $TopdeskPerson = Get-TopdeskPerson  @splatParamsPerson

    if ($outputContext.AuditLogs.isError -contains - $true) {
        Throw "Error(s) occured while looking up required values"
    }
    #endregion lookup
    
    #region Calulate action
    if (-Not([string]::IsNullOrEmpty($TopdeskPerson))) {
        if ($TopdeskPerson.status -eq 'personArchived') {
            $action = 'Enable'
        }   
        else {
            $action = 'NoChanges'
        }
    }
    else {
        $action = 'NotFound' 
    }        

    Write-Verbose "Compared current account to mapped properties. Result: $action"
    #endregion Calulate action

    # region write
    switch ($action) {
        'Enable' {
            Write-Verbose "Activating Topdesk person for: [$($personContext.Person.DisplayName)]"

            # Unarchive person
            $splatParamsPersonUnarchive = @{
                TopdeskPerson   = [ref]$TopdeskPerson
                Headers         = $authHeaders
                BaseUrl         = $actionContext.Configuration.baseUrl
                Archive         = $false
                ArchivingReason = $actionContext.Configuration.personArchivingReason

            }
            if (-Not($actionContext.DryRun -eq $true)) {
                Set-TopdeskPersonArchiveStatus @splatParamsPersonUnarchive

                Write-Information "Account with id [$($TopdeskPerson.id)] and dynamicName [($($TopdeskPerson.dynamicName))] successfully enabled"

                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Account with id [$($TopdeskPerson.id)] and dynamicName [($($TopdeskPerson.dynamicName))] successfully enabled"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "DryRun would unarchive person"
            }

            break
        }
    
        'NoChanges' {
            Write-Information "Account with id [$($TopdeskPerson.id)] and dynamicName [($($TopdeskPerson.dynamicName))] already enabled"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Account with id [$($TopdeskPerson.id)] and dynamicName [($($TopdeskPerson.dynamicName))] already enabled"
                    IsError = $false
                }) 
            break
        }
        'NotFound' {              
            Write-Information "Account with id [$($actionContext.References.Account)] not found"

            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Account with id [$($actionContext.References.Account)] not found"
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
                Action  = "EnableAccount"
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