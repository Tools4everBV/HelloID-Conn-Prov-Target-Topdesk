#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Permissions-Groups
# PowerShell V2
#####################################################

# Initialize default values
$take = 100
$skip = 0

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
#endregion functions

try {

    # Setup authentication headers
    $splatParamsAuthorizationHeaders = @{
        UserName = $actionContext.Configuration.username
        ApiKey   = $actionContext.Configuration.apikey
    }
    $authHeaders = Set-AuthorizationHeaders @splatParamsAuthorizationHeaders

    Write-Information "Searching for person groups"
    $personGroups = [System.Collections.ArrayList]@()
    $paged = $true
    while ($paged) {

        # Get persongroups
        $splatParams = @{
            Uri     = "$($actionContext.Configuration.baseUrl)/tas/api/persongroups/?start=$skip&page_size=$take"
            Method  = 'GET'
            Headers = $authHeaders
        }
        $personGroupsResponse = Invoke-TopdeskRestMethod @splatParams

        # Set $paged to false (to end loop) when response is less than take, indicating there are no more records to query
        if ($personGroupsResponse.id.count -lt $take) {
            $paged = $false;
        }
        # Else: Up skip with take to skip the already queried records
        else {
            $skip = $skip + $take;
        }

        if ($personGroupsResponse -is [array]) {
            [void]$personGroups.AddRange($personGroupsResponse)
        }
        else {
            [void]$personGroups.Add($personGroupsResponse)
        }
    }

    foreach ($group in $personGroups) {
        $outputContext.Permissions.Add(
            @{
                DisplayName    = "Person group - $($group.name)"
                Identification = @{
                    Id = $group.name
                }
            }
        )
    }

}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {

        if (-Not [string]::IsNullOrEmpty($ex.ErrorDetails.Message)) {
            Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.ErrorDetails.Message)"
            Write-Error "Could not retrieve person groups. Error: $($ex.ErrorDetails.Message)"
        }
        else {
            Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
            Write-Error "Could not retrieve person groups. Error: $($ex.Exception.Message)"
        }
    }
    else {
        Write-Information "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not retrieve person groups. Error: $($ex.Exception.Message)"
    }
}