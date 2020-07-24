#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$pRef = $permissionReference | ConvertFrom-json;
$auditMessage = " not created succesfully";

#TOPdesk system data
$url = 'https://tools4ever.topdesk.net'
$apiKey = 'd2tee-hdvxm-wwdvg-o3fkz-ftjcb'
$userName = 'tempadmin'

$path = 'C:\Temp\TOPdesk\exampleChanges.json'

# Enable TLS 1.2
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
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
        
    $uriChanges = $url + "/tas/api/operatorChanges"
    $uriCategories = $url + "/tas/api/incidents/categories"
    $uriSubCategories = $url + "/tas/api/incidents/subcategories"
    $uriRequester = $url + "/tas/api/persons?email=$($changeObject.Requester)"
    $uriTemplates = $url + "/tas/api/applicableChangeTemplates"

    Write-Verbose -Verbose "Creating request for change"
    if ($changeObject.Requester) {
        Write-Verbose -Verbose "Searching for requester $($changeObject.Requester)"
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
        Write-Verbose -Verbose "Added requester $($requesterID.dynamicName) to request"
    }

    if ($changeObject.Request) {
        $requestObject += @{
            request = $changeObject.Request
        }
        Write-Verbose -Verbose "Added request $($changeObject.Request) to request"
    }

    if ($changeObject.Action) {
        $requestObject += @{
            action = $changeObject.Action
        }
        Write-Verbose -Verbose "Added action $($changeObject.Action) to request"
    }

    if ($changeObject.BriefDescription) {
        $requestObject += @{
            briefDescription = $changeObject.BriefDescription
        }
        Write-Verbose -Verbose "Added brief description $($changeObject.BriefDescription) to request"
    }

    if ($changeObject.Template) {
        Write-Verbose -Verbose "Getting templates"
        try {
            $responseTemplates = Invoke-RestMethod -Uri $uriTemplates -Method GET -ContentType $contentType -Headers $headers
            $templateAssign = $responseTemplates.results | Where-Object { ($_.briefDescription -eq $changeObject.Template -or $_.number -eq $changeObject.Template) }
            if ($null -eq $templateAssign) {
                Write-Verbose -Verbose "Template $($changeObject.Template) not found, template is ignored"
            }
            elseif ("2" -le $templateAssign.count) {
                Write-Verbose -Verbose "Multiple templates $($changeObject.template) found, template is ignored"
            }
            else {
                $requestObject += @{
                    template = @{
                        id = $templateAssign.id
                    }
                }
                Write-Verbose -Verbose "Added template '$($templateAssign.briefDescription)' to request"
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
        Write-Verbose -Verbose "Getting categories"
        try {
            $responseCategories = Invoke-RestMethod -Uri $uriCategories -Method GET -ContentType $contentType -Headers $headers
            $categoryAssign = $responseCategories | Where-Object { $_.name -eq $changeObject.Category }
            if ($null -eq $categoryAssign) {
                Write-Verbose -Verbose "Category '$changeObject.Category' not found, category is ignored"
            }
            elseif ("2" -le $categoryAssign.count) {
                Write-Verbose -Verbose "Multiple categories '$changeObject.Category' found, category is ignored"
            }
            else {
                $requestObject += @{
                    category = $categoryAssign.name
                }
                Write-Verbose -Verbose "Added category '$($categoryAssign.name)' to request"
            } 
        }
        catch {
            if ($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request.") {
                $message = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get category '$changeObject.Category', errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }
            else {
                throw "Could not get category '$changeObject.Category', errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    }

    if ($changeObject.SubCategory -and $changeObject.Category) {
        Write-Verbose -Verbose "Getting subcategories"
        try {
            $responseSubCategories = Invoke-RestMethod -Uri $uriSubCategories -Method GET -ContentType $contentType -Headers $headers
            $subCategoryAssign = $responseSubCategories | Where-Object { ($_.name -eq $changeObject.SubCategory) -and ($_.category.name -eq $changeObject.Category) }
            if ($null -eq $subCategoryAssign) {
                Write-Verbose -Verbose "Subcategory '$changeObject.SubCategory' not found, subcategory is ignored"
            }
            elseif ("2" -le $subCategoryAssign.count) {
                Write-Verbose -Verbose "Multiple subcategories '$changeObject.SubCategory' found, subcategory is ignored"
            }
            else {
                Write-Verbose -Verbose "Subcategory '$($subCategoryAssign.name)' belongs to category '$($subCategoryAssign.category.name)'. Assigning categories"
                $requestObject += @{
                    subcategory = $subCategoryAssign.name
                }
                Write-Verbose -Verbose "Added '$($subCategoryAssign.name)' to request"
            } 
        }
        catch {
            if ($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request.") {
                $message = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get subcategory '$changeObject.SubCategory', errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }
            else {
                throw "Could not get subcategory '$changeObject.SubCategory', errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    }

    if ($changeObject.ChangeType) {
        if ($changeObject.ChangeType -eq "simple" -or $changeObject.ChangeType -eq "extensive") {
            $requestObject += @{
                changeType = $changeObject.ChangeType.ToLower()
            }
            Write-Verbose -Verbose "Added change type '$changeObject.ChangeType' to request"
        }
        else {
            if (!$changeObject.Template) {
                Write-Verbose -Verbose "Change type '$changeObject.ChangeType' is not valid and template is not provided. Using 'simple' as change type. Possible entries: 'simple' or 'extensive'"
                $requestObject += @{
                    changeType = "simple"
                }
            }
            elseif ($changeObject.Template -and $templateAssign) {
                Write-Verbose -Verbose "Change type '$changeObject.ChangeType' is not valid, using the value from template '$changeObject.Template'"
            }
            else {
                Write-Verbose -Verbose "Change type '$changeObject.ChangeType' is not valid and the specified template '$changeObject.Template' is provided but was not found. Using 'simple' as change type. Possible entries: 'simple' or 'extensive'"
                $requestObject += @{
                    changeType = "simple"
                }
                Write-Verbose -Verbose "Added change type 'simple' to request"
            }
        }
    }

    if ($changeObject.ExternalNumber) {
        $requestObject += @{
            externalNumber = $changeObject.ExternalNumber
        }
        Write-Verbose -Verbose "Added external number '$changeObject.ExternalNumber' to request"
    }

    if ($changeObject.Impact) {
        $requestObject += @{
            impact = $changeObject.Impact
        }
        Write-Verbose -Verbose "Added impact '$changeObject.Impact' to request"
    }

    if ($changeObject.Benefit) {
        $requestObject += @{
            benefit = $changeObject.Benefit
        }
        Write-Verbose -Verbose "Added benefit '$changeObject.Benefit' to request"
    }

    if ($changeObject.Priority) {
        $requestObject += @{
            priority = $changeObject.Priority
        }
        Write-Verbose -Verbose "Added priority '$changeObject.Priority' to request"
    }
       
    $request = $requestObject | ConvertTo-Json -Depth 10
    try {
        Write-Verbose -Verbose "Starting to create TOPdesk change '$changeObject.BriefDescription'"
        $response = Invoke-RestMethod -Uri $uriChanges -Method POST -ContentType $contentType -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($request)) -UseBasicParsing
    }
    catch {
        if ($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request.") {
            $message = (($_.ErrorDetails.Message | convertFrom-Json).errors).errorCode | Out-String
            throw "Could not create change '$changeObject.BriefDescription', errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
        }
        else {
            throw "Could not create change '$changeObject.BriefDescription', errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
        }
    }
    $change = $response #| ConvertFrom-Json
    Write-Verbose -Verbose "Succesfully created TOPdesk change with id '$($change.id)' and number '$($change.number)', check the Progress Log for details"

    if ($changeObject.Status) {
        $requestObject = @(
            @{
                op    = "replace"
                path  = "/status"
                value = $changeObject.Status
            }
        )
        Write-Verbose -Verbose "Added status '$changeObject.Status' to request"

        $requestBody = ConvertTo-Json $requestObject
        try {
            $response = Invoke-RestMethod -Uri ($uriChanges + "/" + $change.number) -Method PATCH -ContentType $contentType -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($requestBody)) -UseBasicParsing
        }
        catch {
            Write-Verbose -Verbose "Could not update change."
            $message = (($_.ErrorDetails.Message | convertFrom-Json).errors).errorCode | Out-String
            throw "Could not update change '$($change.number)', errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
        }
    }
    return $change
}

$changeList = Get-Content -Raw -Path $path | ConvertFrom-Json
$change = $changeList | Where-Object { $_.Identification.Id -eq $pRef.id } | Select-Object -Property * -ExcludeProperty DisplayName, Identification

if (-Not($dryRun -eq $False)) {
    if (![string]::IsNullOrEmpty($change)) {
        try {
            $change.Request = Invoke-Expression "`"$($change.Request)`""
            $change.BriefDescription = Invoke-Expression "`"$($change.BriefDescription)`""
            $changeResult = New-TOPdeskChange -changeObject $change

            $success = $True;
            $auditMessage = "$($change.BriefDescription) - $($changeResult.number)"
        }
        catch {
            $result = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($result)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $errResponse = $reader.ReadToEnd();
            $auditMessage = "${errResponse}";
        }
    }
}

#build up result
$result = [PSCustomObject]@{ 
    Success          = $success;
    AccountReference = $aRef;
    AuditDetails     = $auditMessage;
    Account          = $account;
};

Write-Output $result | ConvertTo-Json -Depth 10;