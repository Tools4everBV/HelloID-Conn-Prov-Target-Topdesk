#Initialize default properties
$success = $False
$auditMessage = " not granted succesfully"

$p = $person | ConvertFrom-Json
$m = $manager | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$mRef = $managerAccountReference | ConvertFrom-Json
$pRef = $permissionReference | ConvertFrom-json
$config = $configuration | ConvertFrom-Json

#TOPdesk system data
$url = $config.connection.url
$apiKey = $config.connection.apikey
$userName = $config.connection.username
$path = $config.notifications.jsonPath

# Enable TLS 1.2
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
}

function Get-VariablesFromString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $string
    )
    $regex = [regex]'\$\((.*?)\)'
    $variables = [System.Collections.Generic.list[object]]::new()

    $match = $regex.Match($string)
    while ($match.Success) {
        $variables.Add($match.Value)
        $match = $match.NextMatch()
    }
    Write-Output $variables
}

function Resolve-Variables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ref]
        $String,

        [Parameter(Mandatory)]
        $VariablesToResolve
    )
    foreach ($var in $VariablesToResolve | Select-Object -Unique) {
        ## Must be changed When changing the the way of lookup variables.
        $varTrimmed = $var.trim('$(').trim(')')
        $Properties = $varTrimmed.Split('.')

        $curObject = (Get-Variable ($Properties | Select-Object -First 1)  -ErrorAction SilentlyContinue).Value
        $Properties | Select-Object -Skip 1 | ForEach-Object {
            if ($_ -ne $Properties[-1]) {
                $curObject = $curObject.$_
            } elseif ($null -ne $curObject.$_) {
                $String.Value = $String.Value.Replace($var, $curObject.$_)
            } else {
                Write-Verbose  "Variable [$var] not found"
                $String.Value = $String.Value.Replace($var, $curObject.$_) # Add to override unresolved variables with null
            }
        }
    }
}

function Format-Description {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Description
    )
    try {
        $variablesFound = Get-VariablesFromString -String $Description
        Resolve-Variables -String ([ref]$Description) -VariablesToResolve $variablesFound

        Write-Output $Description
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function New-TOPdeskChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $changeObject
    )
    $contentType = "application/json"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
    $base64 = [System.Convert]::ToBase64String($bytes)
    $headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json' }

    $uriChanges = $url + "/operatorChanges"
    $uriRequester = $url + "/persons?email=$($changeObject.Requester)"
    $uriTemplates = $url + "/applicableChangeTemplates"

    Write-Verbose -Verbose -Message "Creating request for change"
    if ($changeObject.Requester) {
        if ($changeObject.Requester -ne "manager" -and $changeObject.Requester -ne "employee") {
            Write-Verbose -Verbose -Message "Searching for requester $($changeObject.Requester)"
            try {
                $requesterSearch = Invoke-RestMethod -Uri $uriRequester -Method GET -ContentType $contentType -Headers $headers -Verbose:$false
            }
            catch {
                if ($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request.") {
                    $message = ($_.ErrorDetails.Message | convertFrom-Json).message
                    throw "Could not get requester $($changeObject.Requester), errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
                }
                else {
                    throw "Could not get requester $($changeObject.Requester), errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
                }
            }

            $requesterID = ($requesterSearch | Where-Object { ($_.email -eq $changeObject.Requester) })
            if (!$requesterID) {
                throw "Could not find requester when searching for requester email $($changeObject.Requester), errorcode: '0x80070057', message: Failed to find requester with email '$Requester'"
            }

            $requestObject += @{
                requester = @{
                    id = $requesterID.id
                }
            }
            Write-Verbose -Verbose -Message "Added requester $($requesterID.dynamicName) to request"
        } else {
            if ($changeObject.Requester -eq "employee") {
                $requestObject += @{
                    requester = @{
                        id = $aRef
                    }
                }
            } else {
                $requestObject += @{
                    requester = @{
                        id = $mRef
                    }
                }
            }
            Write-Verbose -Verbose -Message "Added requester $($changeObject.Requester) to request"
        }
    }

    if ($changeObject.Request) {
        $requestObject += @{
            request = $changeObject.Request
        }
        Write-Verbose -Verbose -Message "Added request $($changeObject.Request) to request"
    }

    if ($changeObject.Action) {
        $requestObject += @{
            action = $changeObject.Action
        }
        Write-Verbose -Verbose -Message "Added action $($changeObject.Action) to request"
    }

    if ($changeObject.BriefDescription) {
        if($changeObject.BriefDescription.Lenth -gt 80){
            $BriefDescription = $changeObject.BriefDescription.SubString(0,80)
        }else{
            $BriefDescription = $changeObject.BriefDescription
        }
        $requestObject += @{
            briefDescription = $BriefDescription
        }
        Write-Verbose -Verbose -Message "Added brief description $($changeObject.BriefDescription) to request"
    }

    if ($changeObject.Template) {
        Write-Verbose -Verbose -Message "Getting template"
        try {
            $responseTemplates = Invoke-RestMethod -Uri $uriTemplates -Method GET -ContentType $contentType -Headers $headers
            $templateAssign = $responseTemplates.results | Where-Object { ($_.briefDescription -eq $changeObject.Template -or $_.number -eq $changeObject.Template) }
            if ($null -eq $templateAssign) {
                Throw "Template '$($changeObject.Template)' not found, does the template exist and is it available for the API?"
            }
            elseif ("2" -le $templateAssign.count) {
                 Throw "Multiple templates $($changeObject.template) found. Cannot continue..."
            }
            else {
                $requestObject += @{
                    template = @{
                        id = $templateAssign.id
                    }
                }
                Write-Verbose -Verbose -Message "Added template '$($templateAssign.briefDescription)' to request"
            }
        }
        catch {
            if ($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request.") {
                $message = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get template $($changeObject.Template), errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }
            else {
                throw "Could not get template $($changeObject.Template), errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    }

     if ($changeObject.Category) {
        Write-Verbose -Verbose -Message "Getting categories"
        # Removed code to retrieve the incident categories for changes as usually these aren't assigned to change templates added in text anyways
        $requestObject += @{
            category = $changeObject.Category
        }
        Write-Verbose -Verbose -Message "Added category '$($changeObject.Category)' to request"
    }

    if ($changeObject.SubCategory -and $changeObject.Category) {
        Write-Verbose -Verbose -Message "Getting subcategories"
        # Removed code to retrieve the incident subcategories for changes as usually these aren't assigned to change templates and they need to be added in text anyways
        $requestObject += @{
            subcategory = $changeObject.SubCategory
        }
        Write-Verbose -Verbose -Message "Added subcategory '$($changeObject.SubCategory)' to request"
    }

    if ($changeObject.ChangeType) {
        if ($changeObject.ChangeType -eq "simple" -or $changeObject.ChangeType -eq "extensive") {
            $requestObject += @{
                changeType = $changeObject.ChangeType.ToLower()
            }
            Write-Verbose -Verbose -Message "Added change type '$($changeObject.ChangeType)' to request"
        }
        else {
            if (!$changeObject.Template) {
                Write-Verbose -Verbose -Message "Change type '$($changeObject.ChangeType)' is not valid and template is not provided. Using 'simple' as change type. Possible entries: 'simple' or 'extensive'"
                $requestObject += @{
                    changeType = "simple"
                }
            }
            elseif ($changeObject.Template -and $templateAssign) {
                Write-Verbose -Verbose -Message "Change type '$($changeObject.ChangeType)' is not valid, using the value from template '$changeObject.Template'"
            }
            else {
                Write-Verbose -Verbose -Message "Change type '$($changeObject.ChangeType)' is not valid and the specified template '$changeObject.Template' is provided but was not found. Using 'simple' as change type. Possible entries: 'simple' or 'extensive'"
                $requestObject += @{
                    changeType = "simple"
                }
                Write-Verbose -Verbose -Message "Added change type 'simple' to request"
            }
        }
    }

    if ($changeObject.ExternalNumber) {
        $requestObject += @{
            externalNumber = $changeObject.ExternalNumber
        }
        Write-Verbose -Verbose -Message "Added external number '$($changeObject.ExternalNumber)' to request"
    }

    if ($changeObject.Impact) {
        $requestObject += @{
            impact = $changeObject.Impact
        }
        Write-Verbose -Verbose -Message "Added impact '$($changeObject.Impact)' to request"
    }

    if ($changeObject.Benefit) {
        $requestObject += @{
            benefit = $changeObject.Benefit
        }
        Write-Verbose -Verbose -Message "Added benefit '$($changeObject.Benefit)' to request"
    }

    if ($changeObject.Priority) {
        $requestObject += @{
            priority = $changeObject.Priority
        }
        Write-Verbose -Verbose -Message "Added priority '$($changeObject.Priority)' to request"
    }

    $request = $requestObject | ConvertTo-Json -Depth 10
    try {
            # get person by ID
            write-verbose -verbose -Message "Person lookup..."
            $PersonUrl = $url + "/persons/id/${aRef}"
            $responsePersonJson = Invoke-WebRequest -uri $PersonUrl -Method Get -Headers $headers -UseBasicParsing
            $responsePerson = $responsePersonJson.Content | Out-String | ConvertFrom-Json

            if ($responsePerson.status -eq "personArchived") {
                write-verbose -verbose -Message "Unarchiving account for '$($p.ExternalID)...'"
                $unarchiveUrl = $PersonUrl + "/unarchive"
                $null = Invoke-WebRequest -uri $unarchiveUrl -Method PATCH -Headers $headers -UseBasicParsing
                write-verbose -verbose -Message "Account unarchived"
            }

        Write-Verbose -Verbose -Message "Starting to create TOPdesk change '$($changeObject.BriefDescription)'"
        $response = Invoke-RestMethod -Uri $uriChanges -Method POST -ContentType $contentType -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($request)) -UseBasicParsing
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq "Bad Request" ) {
            $message = "Could not create change $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            $message = "Could not create change $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'"
        } else {
            $message = "Could not create change $($_.ScriptStackTrace). Error message: '$($_)'"
        }
        Write-Verbose -Verbose -Message $message
        throw
    }
    $change = $response
    Write-Verbose -Verbose -Message "Succesfully created TOPdesk change with id '$($change.id)' and number '$($change.number)', check the Progress Log for details"

    if ($changeObject.Status) {
        $requestObject = @(
            @{
                op    = "replace"
                path  = "/status"
                value = $changeObject.Status
            }
        )
        Write-Verbose -Verbose -Message "Added status '$($changeObject.Status)' to request"

        $requestBody = ConvertTo-Json $requestObject
        try {
            $response = Invoke-RestMethod -Uri ($uriChanges + "/" + $change.number) -Method PATCH -ContentType $contentType -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($requestBody)) -UseBasicParsing
        }
        catch {
            Write-Verbose -Verbose -Message "Could not update change."
            $message = (($_.ErrorDetails.Message | convertFrom-Json).errors).errorCode | Out-String
            throw "Could not update change '$($change.number)', errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
        }
    }
    return $change
}

$changeList = Get-Content -Raw -Path $path | ConvertFrom-Json
$entitlementSet = $changeList | Where-Object {($_.Identification.Id -eq $pRef.id)}
$change = $entitlementSet.Grant

if ([string]::IsNullOrEmpty($entitlementSet)) {
    # Entitlementset niet gevonden...
    write-verbose -Verbose -Message ($entitlementSet | ConvertTo-Json)
    Write-Verbose -Verbose -Message "could not find entitlement set"
    $auditMessage = "Entitlement $($entitlementSet.displayname) not found. Please check the Change definition file at '$path'. If you made changes to the file, please check the file with a JSON validation tool."
    $success = $false
} else {
    # Entitlementset bestaat
    if ($config.notifications.disable -eq $true) {
        $dryRun = $true
        $success = $true
    }

    if (![string]::IsNullOrEmpty($change)) {
        if (-Not($dryRun -eq $True)) {
            #DryRun = False, post change
            try {
                $change.Request = Format-Description -Description $change.Request
                $change.BriefDescription = Format-Description -Description $change.BriefDescription
                $changeResult = New-TOPdeskChange -changeObject $change
                $success = $True
                $auditMessage = "$($change.BriefDescription) - $($changeResult.number)"
            } catch {
                $result = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($result)
                $reader.BaseStream.Position = 0
                $reader.DiscardBufferedData()
                $errResponse = $reader.ReadToEnd();
                $auditMessage = "${errResponse}";
            }
        } else {
            #DryRun = True logging only
            $change.Request = Format-Description -Description $change.Request
            $change.BriefDescription = Format-Description -Description $change.BriefDescription
            Write-Verbose -verbose $($change.request)
            Write-Verbose -verbose $($change.BriefDescription)
        }
    } else {
        #Change is empty
        $auditMessage = "$($entitlementSet.displayname) not created, Grant is not configured."
        if (-Not($dryRun -eq $True)) {
            $success = $true
        }
    }
}

#build up result
$result = [PSCustomObject]@{
    Success          = $success
    AccountReference = $aRef
    AuditDetails     = $auditMessage
    Account          = $account
}

Write-Output $result | ConvertTo-Json -Depth 10
