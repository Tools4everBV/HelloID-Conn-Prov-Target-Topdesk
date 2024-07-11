#####################################################
# HelloID-Conn-Prov-Target-Topdesk-Resource-Departments
# PowerShell V2
#####################################################

# Set to true at start, because only when an error occurs it is set to false
$outputContext.Success = $true

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

function Get-TopdeskDepartments {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $baseUrl,
        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$baseUrl/tas/api/departments"
        Method  = 'GET'
        Headers = $Headers
    }
    $responseGet = Invoke-TopdeskRestMethod @splatParams
    Write-Verbose "Retrieved $($responseGet.count) department from Topdesk"
    Write-Output $responseGet
}

function New-TopdeskDepartment {
    param (
        [ValidateNotNullOrEmpty()]
        [string]
        $Name,

        [ValidateNotNullOrEmpty()]
        [string]
        $BaseUrl,

        [System.Collections.IDictionary]
        $Headers
    )

    $splatParams = @{
        Uri     = "$BaseUrl/tas/api/departments"
        Method  = 'POST'
        Headers = $Headers
        body    = @{name = $Name } | ConvertTo-Json
    }
    $responseCreate = Invoke-TopdeskRestMethod @splatParams
    Write-Verbose "Created department with name [$($name)] and id [$($responseCreate.id)] in Topdesk"
    Write-Output $responseCreate
}
#endregion functions

#Begin
try {
    # Setup authentication headers    
    $splatParamsAuthorizationHeaders = @{
        UserName = $actionContext.Configuration.username
        ApiKey   = $actionContext.Configuration.apikey
    }
    $authHeaders = Set-AuthorizationHeaders @splatParamsAuthorizationHeaders
    
    # Get department
    $splatParamsDepartments = @{
        Headers = $authHeaders
        BaseUrl = $actionContext.Configuration.baseUrl
    }
    $TopdeskDepartments = Get-TopdeskDepartments @splatParamsDepartments

    # Remove items with no name
    $TopdeskDepartments = $TopdeskDepartments.Where({ $_.Name -ne "" -and $_.Name -ne $null })
    $rRefSourceData = $resourceContext.SourceData.Where({ $_.displayName -ne "" -and $_.displayName -ne $null })

    # Process
    foreach ($HelloIdDepartment in $rRefSourceData) {
        if (-not($TopdeskDepartments.Name -eq $HelloIdDepartment.displayName)) {
            if (-not ($actionContext.DryRun -eq $true)) {
                Write-Verbose "Creating Topdesk department with the name [$($HelloIdDepartment.displayName)] in Topdesk."
                # Create department
                $splatParamsCreateDepartment = @{
                    Headers = $authHeaders
                    BaseUrl = $actionContext.Configuration.baseUrl
                    Name    = $HelloIdDepartment.displayName
                }
                $newDepartment = New-TopdeskDepartment @splatParamsCreateDepartment
                    
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = "CreateResource"    
                        Message = "Created Topdesk department with the name [$($newDepartment.name)] and ID [$($newDepartment.id)]"
                        IsError = $false
                    })
            }
            else {
                Write-Warning "Preview: Would create Topdesk department $($HelloIdDepartment.displayName)"
            }
        }
        else {
            Write-Verbose "Not creating department [$($HelloIdDepartment.displayName)] as it already exists in Topdesk"
        }
    }
}
catch {
    $ex = $PSItem
    
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorMessage = "Could not create department [$($HelloIdDepartment.displayName)]. Error:  $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }
    else {
        $errorMessage = "Could not create department [$($HelloIdDepartment.displayName)]. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = "CreateResource"    
            Message = $errorMessage
            IsError = $true
        })
}
finally {
    # Check if auditLogs contains errors, if errors are found, set success to false
    if ($outputContext.AuditLogs.IsError -contains $true) {
        $outputContext.Success = $false
    }
}