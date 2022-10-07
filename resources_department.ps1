#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Resource-Departments
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$rRef = $resourceContext | ConvertFrom-Json

$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
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

function Invoke-TOPdeskRestMethod {
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

function Get-TOPdeskDepartments {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,
        
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$baseUrl/tas/api/departments"
        Method  = 'GET'
        Headers = $Headers
    }

    $responseGet = Invoke-TOPdeskRestMethod @splatParams
    Write-Verbose "Retrieved $($responseGet.count) departments from TOPdesk"
    Write-Output $responseGet
}

function New-TOPdeskDepartment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        
        $BaseUrl,
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/departments"
        Method  = 'POST'
        Headers = $Headers
        body    = @{name=$Name} | ConvertTo-Json
    }
    $responseCreate = Invoke-TOPdeskRestMethod @splatParams
    Write-Verbose "Created department with name [$($name)] and id [$($responseCreate.id)] in TOPdesk"
    Write-Output $responseCreate
}


function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory,
            ValueFromPipeline
        )]
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
#endregion

#Begin
try {
    $authHeaders = Set-AuthorizationHeaders -UserName $Config.username -ApiKey $Config.apikey
    $TopdeskDepartments = Get-TOPdeskDepartments -Headers $authHeaders -BaseUrl $Config.baseUrl

    # Remove items with no name
    $TopdeskDepartments = $TopdeskDepartments.Where({ $_.Name -ne "" -and  $_.Name -ne $null })
    $rRefSourceData = $rRef.sourceData.Where({ $_.displayName -ne "" -and  $_.displayName -ne $null })
    
    # Process
    $success = $true
    foreach ($HelloIdDepartment in $rRefSourceData) {
        
        if (-not($TopdeskDepartments.name -contains $HelloIdDepartment.displayName)) {
            # Create department
            if (-not ($dryRun -eq $true)) {
                try {
                    write-verbose ($HelloIdDepartment | ConvertTo-Json)
                    Write-Verbose "Creating TOPdesk department with the name [ $($HelloIdDepartment.displayName) ] in TOPdesk..."
                    $newDepartment = New-TOPdeskDepartment -Name $HelloIdDepartment.displayName -BaseUrl $Config.baseUrl -Headers $authHeaders
                    
                    $auditLogs.Add([PSCustomObject]@{
                        Message = "Created TOPdesk department with the name [$($newDepartment.name)] and ID [$($newDepartment.id)]"
                        IsError = $false
                    })
                } catch {
                    $success = $false
                    $ex = $PSItem
                    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
                        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
                        $errorMessage = "Could not create department. Error: $($ex.ErrorDetails.Message)"
                    } else {
                        $errorMessage = "Could not create department. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
                    }
                    Write-Verbose "$errorMessage"
                    $auditLogs.Add([PSCustomObject]@{
                        Message = $errorMessage
                        IsError = $true
                    })
                }
            } else {
                Write-Verbose "Preview: Would create topdesk department $($HelloIdDepartment.displayName)"
            }
        } else {
            Write-Verbose "Not creating department [$($HelloIdDepartment.displayName)] as it already exists in TOPdesk"
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    #write-verbose ($ex.Exception.message | ConvertTo-Json)
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-HTTPError -ErrorObject $ex
        $errorMessage = "Could not read or create departments. Error: $($errorObj.ErrorMessage)"
    } else {
        $errorMessage = "Could not read or create departments. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }
    $auditLogs.Add([PSCustomObject]@{
        Message = $errorMessage
        IsError = $true
    })
# End
} finally {
   $result = [PSCustomObject]@{
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}