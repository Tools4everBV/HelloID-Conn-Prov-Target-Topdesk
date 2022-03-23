#####################################################
# HelloID-Conn-Prov-Target-TOPdesk-Resource
#
# Version: 1.0.0
#####################################################
$resourceContext = '{ "SourceData": [ { "externalId": "13", "displayName": "Administration" }, { "externalId": "14", "displayName": "Support" }, { "externalId": "15", "displayName": "Projectcoördinatie" }, { "externalId": "16", "displayName": "Inside Sales" }, { "externalId": "17", "displayName": "Consultancy" }, { "externalId": "19", "displayName": "Systeembeheer" }, { "externalId": "21", "displayName": "Directie" }, { "externalId": "22", "displayName": "Development" }, { "externalId": "23", "displayName": "Existing Business" } ] }'
$configuration  = '{ "connection": { "baseUrl": "https://tools4ever.topdesk.net", "username": "tempadmin", "apikey": "d2tee-hdvxm-wwdvg-o3fkz-ftjcb" }, "notifications": { "jsonPath": "C:\\HelloID\\TOPdesk\\TOPdeskEntitlementTemplates.json", "disable": true }, "isDebug": true, "lookup": { "errorDepartment": "true", "errorCostCenter": "true", "errorBudgetHolder": "true", "errorNoManager": "true" } }'

# Initialize default value's
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
    param ()
    process {
        # Create basic authentication string
        $bytes = [System.Text.Encoding]::ASCII.GetBytes("$($config.connection.userName):$($config.connection.apiKey)")
        $base64 = [System.Convert]::ToBase64String($bytes)

        # Set authentication headers
        $authHeaders = New-Object "System.Collections.Generic.Dictionary[[String], [String]]"
        $authHeaders.Add("Authorization", "BASIC $base64")
        $authHeaders.Add("Accept", 'application/json')
        Write-Output $authHeaders
    }
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
                Write-Verbose 'Adding body to request'
                $splatParams['Body'] = [Text.Encoding]::UTF8.GetBytes($Body)
            }
            Invoke-RestMethod @splatParams -Verbose:$true
        } catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}
# function Resolve-HTTPError {
#     [CmdletBinding()]
#     param (
#         [Parameter(Mandatory,
#             ValueFromPipeline
#         )]
#         [object]$ErrorObject
#     )
#     process {
#         $httpErrorObj = [PSCustomObject]@{
#             FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
#             MyCommand             = $ErrorObject.InvocationInfo.MyCommand
#             RequestUri            = $ErrorObject.TargetObject.RequestUri
#             ScriptStackTrace      = $ErrorObject.ScriptStackTrace
#             ErrorMessage          = ''
#         }
#         if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
#             $httpErrorObj.ErrorMessage = $ErrorObject.ErrorDetails.Message
#         } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
#             $httpErrorObj.ErrorMessage = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
#         }
#         Write-Output $httpErrorObj
#     }
# }

function Get-TOPdeskDepartments {
    [CmdletBinding()]
    param ()
    $splatGoupParams = @{
        Uri     = "$($config.connection.baseUrl)/tas/api/departments"
        Method  = 'GET'
        Headers = Set-AuthorizationHeaders
    }
    $responseGetGroup = Invoke-RestMethod @splatGoupParams
    Write-Verbose "Retrieved $($responseGetGroup.count) departments from TOPdesk"
    return $responseGetGroup
}

function New-TOPdeskDepartment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
    )

    #duplicate message Write-Verbose -Verbose -Message "Creating department with name [$($name)] in TOPdesk"
    $splatParams = @{
        Uri     = "$($config.connection.baseUrl)/tas/api/departments"
        Method  = 'POST'
        Headers = Set-AuthorizationHeaders
        body    = @{name=$Name} | ConvertTo-Json
    }
    $responseCreateDepartment = Invoke-TOPdeskRestMethod @splatParams
    Write-Verbose "Created department with name [$($name)] and id [$($responseCreateDepartment.id)] in TOPdesk"
    return $responseCreateDepartment
}
#endregion

#Begin
try {
    $TopdeskDepartments = Get-TOPdeskDepartments

    # Remove items with no name
    [Void]$TopdeskDepartments.Where({ $_.Name-ne "" })
    [Void]$rRef.sourceData.Where({ $_.DisplayName -ne "" })

    # Check for duplicates? ---- All duplicates should generate an error
    #$b = $TopdeskDepartments | select –unique
    #Compare-object –referenceobject $b –differenceobject $a

    # Process
    <# Resource creation preview uses a timeout of 30 seconds, while actual run has timeout of 10 minutes #>
    $success = $true
    foreach ($HelloIdDepartment in $rRef.sourceData) {
        if (-not($TopdeskDepartments.Name -contains $HelloIdDepartment.displayName)) {
            # Create department
            if (-not ($dryRun -eq $true)) {
                try {
                    Write-Verbose "Creating TOPdesk department with the name [$($HelloIdDepartment.displayName)] in TOPdesk..."

                    # Create action
                    $newDepartment = New-TOPdeskDepartment -Name $HelloIdDepartment.displayName

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
                Write-Verbose "Would create topdesk department $($HelloIdDepartment.displayName)"
            }
        } else {
            Write-Verbose "Not creating department [$($HelloIdDepartment.displayName)] as it already exists in TOPdesk"
        }
    }
} catch {
    $success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorMessage = "Could not create department. Error: $($ex.ErrorDetails.Message)"
    } else {
        $errorMessage = "Could not create department. Error: $($ex.Exception.Message) $($ex.ScriptStackTrace)"
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
    #Write-Output $result | ConvertTo-Json -Depth 10
}
