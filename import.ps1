#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Import
# PowerShell V2
#####################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

try {
    Write-Information 'Starting target account import'

    $importFields = $($actionContext.ImportFields)
    
    # Remove all '.' and the value behind. For example branch instead of branch.name
    $importFields = $importFields -replace '\..*', ''

    # Gender is not a supported field to query (APIv2), if exists it will be filtered
    $importFields = $importFields | Where-Object { $_ -ne 'gender' }

    # Add mandatory fields for HelloID to query and return
    if ('id' -notin $importFields) { $importFields += 'id' }
    if ('archived' -notin $importFields) { $importFields += 'archived' }
    if ('dynamicName' -notin $importFields) { $importFields += 'dynamicName' }
    if ('tasLoginName' -notin $importFields) { $importFields += 'tasLoginName' }

    # Remove fields from other endpoints
    if ('privateDetails' -in $importFields) { $importFields = $importFields | Where-Object { $_ -ne 'privateDetails' } }
    if ('contract' -in $importFields) { $importFields = $importFields | Where-Object { $_ -ne 'contract' } }

    # Convert to a ',' string
    $fields = $importFields -join ','
    Write-Information "Querying fields [$fields]"

    # Create basic authentication string
    $username = $actionContext.Configuration.username
    $apikey = $actionContext.Configuration.apikey
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("${username}:${apikey}")
    $base64 = [System.Convert]::ToBase64String($bytes)

    # Set authentication headers
    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add("Authorization", "BASIC $base64")
    $headers.Add('Accept', 'application/x.topdesk-collection-person-v2+json')

    $existingAccounts = @()
    $pageSize = 5000
    $uri = "$($actionContext.Configuration.baseUrl)/tas/api/persons?pageStart=0&pageSize=$pageSize&fields=$fields"
    
    do {
        $splatParams = @{
            Uri         = $uri
            Headers     = $headers
            Method      = 'GET'
            ContentType = 'application/json; charset=utf-8'
        }
    
        $partialResultUsers = Invoke-RestMethod @splatParams
        $existingAccounts += $partialResultUsers.item
        $uri = $partialResultUsers.next

        Write-Information "Successfully queried [$($existingAccounts.count)] existing accounts"
    } while ($uri)

    # Map the imported data to the account field mappings
    foreach ($account in $existingAccounts) {
        $enabled = $true
        # Convert archived to disabled
        if ($account.archived) {
            $enabled = $false
        }

        # Make sure the DisplayName has a value
        if ([string]::IsNullOrEmpty($account.dynamicName)) {
            $account.dynamicName = $account.id
        }

        # Make sure the Username has a value
        if ([string]::IsNullOrEmpty($account.tasLoginName)) {
            $account.tasLoginName = $account.id
        }

        # Return the result
        Write-Output @{
            AccountReference = $account.id
            DisplayName      = $account.dynamicName
            UserName         = $account.tasLoginName
            Enabled          = $enabled
            Data             = $account
        }
    }
    Write-Information 'Target account import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.ErrorDetails.Message)"
            Write-Error "Could not import account entitlements. Error: $($ex.ErrorDetails.Message)"
        }
        else {
            Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            Write-Error "Could not import account entitlements. Error: $($ex.Exception.Message)"
        }
    }
    else {
        Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import account entitlements. Error: $($ex.Exception.Message)"
    }
}