#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Permissions-Groups-Revoke
# PowerShell V2
#####################################################

# Note: There is currently no way to directly link persongroups to a person.
# Instead, we use Selections in TOPdesk to sync persons to a group once per day.
# We use 'Contains' criteria based on a selected field, which TOPdesk uses to sync the users. 
# This script only updates the Person field which is configured in the script. Be wary of character limits of 100 characters.
# See: https://docs.topdesk.com/en/linking-a-person-to-a-person-group-265628.html#UUID-87681fa9-294a-64d0-0cad-caee8c17bbd8

$PersonField = "optionalFields1.text2"

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
    $authHeaders.Add('Partner-Solution-Id', 'TOOL001') # Fixed value - Tools4ever Partner Solution ID

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

function New-TopdeskBodyRemove {
    param(
        [string]$PersonField,  # veldnaam
        [string]$Value,        # te verwijderen waarde
        [string]$FieldValue    # bestaande waarde
    )

    $parts = $PersonField -split '\.'

    # Split bestaande waarde in array
    $values = @()
    if (-not [string]::IsNullOrWhiteSpace($FieldValue)) {
        $values = $FieldValue -split ';'
    }

    # Exclude de waarde die we moeten removen
    $newValues = $values | Where-Object { $_ -ne $Value -and -not [string]::IsNullOrWhiteSpace($_) }

    # Maak er weer een string van, of leeg als er niets meer over is
    if ($newValues.Count -gt 0) {
        $newValue = ($newValues -join ';')
    }
    else {
        $newValue = $null  # hele attribuut leegmaken
    }

    # Hashtable teruggeven
    if ($parts.Count -eq 1) {
        return @{ $parts[0] = $newValue }
    }
    elseif ($parts.Count -eq 2) {
        return @{ $parts[0] = @{ $parts[1] = $newValue } }
    }
    else {
        throw "Meer dan 2 niveaus wordt niet ondersteund."
    }
}
#endregion functions

try {
    # Setup authentication headers
    $splatParamsAuthorizationHeaders = @{
        UserName = $actionContext.Configuration.username
        ApiKey   = $actionContext.Configuration.apikey
    }
    $authHeaders = Set-AuthorizationHeaders @splatParamsAuthorizationHeaders

    Write-Information "Setting field '$PersonField' for person $($personContext.Person.Displayname)"
    
    $splatParamsPerson = @{
        AccountReference = $actionContext.References.Account
        Headers          = $authHeaders
        BaseUrl          = $actionContext.Configuration.baseUrl
    }
    $TopdeskPerson = Get-TopdeskPerson  @splatParamsPerson

    if (-Not([string]::IsNullOrEmpty($TopdeskPerson))) {
        
        # Check if the field contains the groupname
        $fieldValue = $TopdeskPerson
        foreach ($part in $PersonField -split '\.') {
            $fieldValue = $fieldValue.$part
        }

        $FieldValues = $fieldValue -split ';'

        # Split PermissionDisplayname value into searchable value
        $GroupName = $($actionContext.References.Permission.Id)

        if ($FieldValues -contains $GroupName) {
            $action = 'RemoveGroupname'
        }
        else {
            $action = 'NoChanges'
        } 

        switch ($action) {
            'RemoveGroupname' {
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
                Write-Information "Updating Topdesk person field: $PersonField for: [$($personContext.Person.DisplayName)]"
                        
                $body = New-TopdeskBodyRemove -PersonField $PersonField -Value $GroupName -FieldValue $fieldValue

                $splatParamsPersonUpdate = @{
                    TopdeskPerson = $TopdeskPerson
                    Account       = $body
                    Headers       = $authHeaders
                    BaseUrl       = $actionContext.Configuration.baseUrl
                }

                if (-Not($actionContext.DryRun -eq $true)) {
                    $TopdeskPersonUpdated = Set-TopdeskPerson @splatParamsPersonUpdate

                    Write-Information "Account with id [$($TopdeskPerson.id)] successfully updated. $PersonField subtracted with $GroupName."

                    $outputContext.AuditLogs.Add([PSCustomObject]@{
                            Message = "Account with id [$($TopdeskPerson.id)] successfully updated. $PersonField subtracted with $GroupName."
                            IsError = $false
                        })
                }
                else {
                    Write-Warning "DryRun would subtract $PersonField with $GroupName."
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
                
                break
            }
        
            'NoChanges' {        
                Write-Information "Account with id [$($TopdeskPerson.id)] not updated. $PersonField already does not contain $GroupName. No changes required."
                break
            }

        }
              
    }    

}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.ErrorDetails.Message)"
            Write-Error "Could not update person field $PersonField. Error: $($ex.ErrorDetails.Message)"
        }
        else {
            Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            Write-Error "Could not update person field $PersonField. Error: $($ex.Exception.Message)"
        }
    }
    else {
        Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not update person field $PersonField. Error: $($ex.Exception.Message)"
    }
}
finally {
    # Check if auditLogs contains errors, if no errors are found, set success to true
    if ($outputContext.AuditLogs.IsError -notContains $true) {
        $outputContext.Success = $true
    }
}