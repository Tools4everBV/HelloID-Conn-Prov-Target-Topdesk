#Initialize default properties
$success = $False;

$p = $person | ConvertFrom-Json;
$aRef = $accountReference | ConvertFrom-Json;
$pRef = $permissionReference | ConvertFrom-json;
$config = $configuration | ConvertFrom-Json 
$auditMessage = " not created succesfully";

#TOPdesk system data
$url = $config.connection.url
$apiKey = $config.connection.apikey
$userName = $config.connection.username
$path = $config.notifications.jsonPath

# Enable TLS 1.2
if ([Net.ServicePointManager]::SecurityProtocol -notmatch "Tls12") {
    [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
}
function New-TopdeskIncident{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $incidentObject
    )
    $contentType = "application/json"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
    $base64 = [System.Convert]::ToBase64String($bytes)
    $headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json' }
        
    $uriIncidents = $url + "/tas/api/incidents"
    $uriBranch = $url + "/tas/api/branches"
    $uriIncidents = $url + "/tas/api/incidents"
    $uriImpacts = $url + "/tas/api/incidents/impacts"
    $uriOperatorGroups = $url + "/tas/api/operatorgroups"
    $uriProcessingStatus = $url + "/tas/api/incidents/processing_status"
    $uriPriorities = $url + "/tas/api/incidents/priorities"
    $uriCategories = $url + "/tas/api/incidents/categories"
    $uriSubCategories = $url + "/tas/api/incidents/subcategories"
    $uriEntryTypes = $url + "/tas/api/incidents/entry_types"
    $uriCallTypes = $url + "/tas/api/incidents/call_types"
    $uriCallerEmail = $url + "/tas/api/persons?email=$CallerEmail"
    $uriUrgencies = $url + "/tas/api/incidents/urgencies"

    Write-Verbose -Verbose "Creating request for incident"
    if($incidentObject.Branch){
        Write-Verbose -Verbose "Branch is specified. Checking whether the branch exists"
        try{
            $responseBranches = Invoke-WebRequest -Uri $uriBranch -Method GET -ContentType $contentType -Headers $headers | ConvertFrom-Json
            $branchAssign = $responseBranches | Where-Object{$_.name -eq $incidentObject.Branch} 
            if($null -eq $branchAssign){
                Write-Verbose -Verbose "Branch '$incidentObject.Branch' not found, branch is ignored"
            }elseif("2" -le $branchAssign.count){
                Write-Verbose -Verbose "Multiple Branches '$incidentObject.Branch' found, branch is ignored"            
            }else{
                $requestObject += @{
                    branch = @{
                        id = $branchAssign.id
                    }
                }
                Write-Verbose -Verbose "Added branch '$($branchAssign.name)' to the request"
            }
        }catch{
            if($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request."){
                $message  = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get branches, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }else{
                throw "Could not get branches, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    }

    if($incidentObject.OperatorGroup){
        Write-Verbose -Verbose "Getting operator groups"
        try{
            $responseOperatorGroups = Invoke-WebRequest -Uri $uriOperatorGroups -Method GET -ContentType $contentType -Headers $headers | ConvertFrom-Json
            $operatorGroupAssign = $responseOperatorGroups | Where-Object{$_.groupName -eq $incidentObject.OperatorGroup}
            if($null -eq $operatorGroupAssign){
                Write-Verbose -Verbose "Operator group '$incidentObject.OperatorGroup' not found, operator group is ignored"
            }elseif("2" -le $operatorGroupAssign.count){
                Write-Verbose -Verbose "Multiple operator groups '$incidentObject.OperatorGroup' found, operator group is ignored"
            }else{
                $requestObject += @{
                    operatorGroup = @{
                        id = $operatorGroupAssign.id
                    }
                }
                Write-Verbose -Verbose "Added operator group '$($operatorGroupAssign.groupName)' to request"
            }
        }catch{
            if($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request."){
                $message  = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get operator groups, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }else{
                throw "Could not get operator groups, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    }
    
    if(!$incidentObject.ProcessingStatus -and $incidentObject.CloseTicket -eq "True"){
        Write-Verbose -Verbose "The ticket needs to be closed, but no processing status has been given. Searching for closed processing status"
        Add-Member -InputObject $incidentObject -NotePropertyName ProcessingStatus -NotePropertyValue Closed
    }

    if($incidentObject.ProcessingStatus){
        Write-Verbose -Verbose "Getting processing states"
        try{
            $responseProcessingStatus = Invoke-WebRequest -Uri $uriProcessingStatus -Method GET -ContentType $contentType -Headers $headers | ConvertFrom-Json
            $processingStatusAssign = $responseProcessingStatus | Where-Object{$_.name -eq $incidentObject.ProcessingStatus -or $_.processingState -eq $incidentObject.ProcessingStatus}
            if($null -eq $processingStatusAssign){
                Write-Verbose -Verbose "Processing status '$incidentObject.ProcessingStatus' not found, processing status is ignored"
            }elseif("2" -le $processingStatusAssign.count){
                Write-Verbose -Verbose "Multiple processing statusses '$incidentObject.ProcessingStatus' found, processing status is ignored"         
            }else{
                $requestObject += @{
                    processingStatus = @{
                        id = $processingStatusAssign.id
                    }
                }
                Write-Verbose -Verbose "Added processing status '$($processingStatusAssign.name)' to request"
                if($processingStatusAssign.processingState -ne "Closed" -and $incidentObject.CloseTicket -eq "True"){
                    Write-Verbose -Verbose "Processing status '$($processingStatusAssign.name)' does not have a closed state, so close incident is ignored"
                }
            } 
        }catch{
            if($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request."){
                $message  = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get processing status, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }else{
                throw "Could not get processing status, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    } 
    
    if($incidentObject.Category){
        Write-Verbose -Verbose "Getting categories"
        try{
            $responseCategories = Invoke-WebRequest -Uri $uriCategories -Method GET -ContentType $contentType -Headers $headers | ConvertFrom-Json
            $categoryAssign = $responseCategories | Where-Object{$_.name -eq $incidentObject.Category}
            if($null -eq $categoryAssign){
                Write-Verbose -Verbose "Category '$incidentObject.Category' not found, category is ignored"
            }elseif("2" -le $categoryAssign.count){
                Write-Verbose -Verbose "Multiple categories '$incidentObject.Category' found, category is ignored"r            
            }else{
                $requestObject += @{
                    category = @{
                        id = $categoryAssign.id
                    }
                }
                Write-Verbose -Verbose "Added category '$($categoryAssign.name)' to request"
            } 
        }catch{
            if($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request."){
                $message  = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get category errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }else{
                throw "Could not get category, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    } 

    if($incidentObject.SubCategory -and $incidentObject.Category){
        Write-Verbose -Verbose "Getting subcategories"
        try{
            $responseSubCategories = Invoke-WebRequest -Uri $uriSubCategories -Method GET -ContentType $contentType -Headers $headers | ConvertFrom-Json
            $subCategoryAssign = $responseSubCategories | Where-Object{($_.name -eq $incidentObject.SubCategory) -and ($_.category.name -eq $incidentObject.Category)}
            if($null -eq $subCategoryAssign){
                Write-Verbose -Verbose "Subcategory '$incidentObject.SubCategory' not found, subcategory is ignored"
            }elseif("2" -le $subCategoryAssign.count){
                Write-Verbose -Verbose "Multiple subcategories '$incidentObject.SubCategory' found, subcategory is ignored"            
            }else{
                Write-Verbose -Verbose "Subcategory '$($subCategoryAssign.name)' belongs to category '$($subCategoryAssign.category.name)'. Assigning categories"
                $requestObject += @{
                    subcategory = @{
                        id = $subCategoryAssign.id
                    }
                }
                Write-Verbose -Verbose "Added subcategory '$($subCategoryAssign.name)' to request"
            } 
        }catch{
            if($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request."){
                $message  = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get categories, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }else{
                throw "Could not get categories, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    }
    
    if($incidentObject.Impact){
        Write-Verbose -Verbose "Getting impacts"
        try{
            $responseImpacts = Invoke-WebRequest -Uri $uriImpacts -Method GET -ContentType $contentType -Headers $headers | ConvertFrom-Json
            $impactAssign = $responseImpacts | Where-Object{$_.name -eq $incidentObject.Impact}
            if($null -eq $impactAssign){
                Write-Verbose -Verbose "Impect '$incidentObject.Impact' not found, impact is ignored"
            }elseif("2" -le $impactAssign.count){
                Write-Verbose -Verbose "Multiple impacts '$incidentObject.Impact' found, impact is ignored"            
            }else{
                $requestObject += @{
                    impact = @{
                        id = $impactAssign.id
                    }
                }
                Write-Verbose -Verbose "Added impact '$($impactAssign.name)' to request"
            } 
        }catch{
            if($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request."){
                $message  = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get impact, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }else{
                throw "Could not get impact, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    }

    if($incidentObject.Urgency){
        Write-Verbose -Verbose "Getting urgencies"
        try{
            $responseUrgencies = Invoke-WebRequest -Uri $uriUrgencies -Method GET -ContentType $contentType -Headers $headers | ConvertFrom-Json
            $urgencyAssign = $responseUrgencies | Where-Object{$_.name -eq $incidentObject.Urgency}
            if($null -eq $urgencyAssign){
                Write-Verbose -Verbose "Urgency '$incidentObject.Urgency' not found, urgency is ignored"
            }elseif("2" -le $urgencyAssign.count){
                Write-Verbose -Verbose "Multiple urgencies '$incidentObject.Urgency' found, urgency is ignored"           
            }else{
                $requestObject += @{
                    urgency = @{
                        id = $urgencyAssign.id
                    }
                }
                Write-Verbose -Verbose "Added urgency '$($urgencyAssign.name)' to request"
            } 
        }catch{
            if($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request."){
                $message  = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get urgency, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }else{
                throw "Could not get urgency, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    } 

    if($incidentObject.Priority){
        Write-Verbose -Verbose "Getting priorities"
        try{
            $responsePriorities = Invoke-WebRequest -Uri $uriPriorities -Method GET -ContentType $contentType -Headers $headers | ConvertFrom-Json
            $priorityAssign = $responsePriorities | Where-Object{$_.name -eq $incidentObject.Priority}
            if($null -eq $priorityAssign){
                Write-Verbose -Verbose "Priority '$incidentObject.Priority' not found, priority is ignored"
            }elseif("2" -le $priorityAssign.count){
                Write-Verbose -Verbose "Multiple priorities '$incidentObject.Priority' found, priority is ignored"            
            }else{
                $requestObject += @{
                    priority = @{
                        id = $priorityAssign.id
                    }
                }
                Write-Verbose -Verbose "Added priority '$($priorityAssign.name)' to request"
            } 
        }catch{
            if($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request."){
                $message  = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get priority, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }else{
                throw "Could not get priority, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    } 

    if($incidentObject.CallType){
        Write-Verbose -Verbose "Getting calltypes"
        try{
            $responseCallTypes = Invoke-WebRequest -Uri $uriCallTypes -Method GET -ContentType $contentType -Headers $headers | ConvertFrom-Json
            $callTypeAssign = $responseCallTypes | Where-Object{$_.name -eq $incidentObject.CallType}
            if($null -eq $callTypeAssign){
                Write-Verbose -Verbose "Call type '$incidentObject.CallType' not found, call type is ignored"
            }elseif("2" -le $callTypeAssign.count){
                Write-Verbose -Verbose "Multiple call types '$incidentObject.CallType' found, call type is ignored"       
            }else{
                $requestObject += @{
                    callType = @{
                        id = $callTypeAssign.id
                    }
                }
                Write-Verbose -Verbose "Added call type '$($callTypeAssign.name)' to request"
            } 
        }catch{
            if($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request."){
                $message  = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get call type, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }else{
                throw "Could not get call type, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    } 

    if($incidentObject.Entry){
        Write-Verbose -Verbose "Getting Entry types" -Event Information
        try{
            $responseEntryTypes = Invoke-WebRequest -Uri $uriEntryTypes -Method GET -ContentType $contentType -Headers $headers | ConvertFrom-Json
            $entryTypeAssign = $responseEntryTypes | Where-Object{$_.name -eq $incidentObject.Entry}
            if($null -eq $entryTypeAssign){
                Write-Verbose -Verbose "Entry type '$incidentObject.Entry' not found, entry type is ignored"
            }elseif("2" -le $entryTypeAssign.count){
                Write-Verbose -Verbose "Multiple entry types '$incidentObject.Entry' found, entry type is ignored"
            }else{
                $requestObject += @{
                    entryType = @{
                        id = $entryTypeAssign.id
                    }
                }
                Write-Verbose -Verbose "Added entry type '$($entryTypeAssign.name)' to request"
            } 
        }catch{
            if($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request."){
                $message  = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get entry type, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }else{
                throw "Could not get entry type, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    }

    if($incidentObject.CallerEmail){
        try{
            $responseCallerEmail = Invoke-WebRequest -Uri $uriCallerEmail -Method GET -ContentType $contentType -Headers $headers | ConvertFrom-Json
            $callerEmailAssign = $responseCallerEmail | Where-Object{$_.email -eq $incidentObject.CallerEmail}
            if($null -eq $callerEmailAssign){
                throw "Caller email '$CallerEmail' not found, a valid caller email must be specified"
            }elseif("2" -le $callTypeAssign.count){
                throw "Multiple caller emails '$CallerEmail' found, specify a unique caller email"            
            }else{
                $requestObject += @{
                    callerLookup = @{
                        email = $callerEmailAssign.email
                    }
                }
                Write-Verbose -Verbose "Added caller email '$($callerEmailAssign.email)' to request"
            } 
        }catch{
            if($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request."){
                $message  = ($_.ErrorDetails.Message | convertFrom-Json).message
                throw "Could not get caller email, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
            }else{
                throw "Could not get caller email, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
            }
        }
    }

    if($incidentObject.Status){
        $requestObject += @{
                status = "secondLine"
        }       
    }else{
        $requestObject += @{
            status = "firstLine"
        } 
    }
    Write-Verbose -Verbose "Added status '$($requestObject.status)' to request"


    if($incidentObject.TargetDate){
        try{
            $datetime = [System.DateTime]::ParseExact($incidentObject.TargetDate,"dd-MM-yyyy",$null)
            $requestObject += @{
                targetDate = $datetime.ToString("yyyy-MM-ddTHH:mm:ms.fffzz00")
            }
            Write-Verbose -Verbose "Added target date '$incidentObject.TargetDate' to request"
        }catch{
            Write-Verbose -Verbose "The target date '$incidentObject.TargetDate' has an invalid format. The incident will be created without a target date."
        } 
    }

    if($incidentObject.ObjectId){
        $requestObject += @{
            object = @{
                name = $ObjectId
            }
        }
        Write-Verbose -Verbose "Added object ID '$incidentObject.ObjectId' to request"
    }
    if($incidentObject.RequestDescription){
        $requestObject += @{
            request = $incidentObject.RequestDescription
        }
        Write-Verbose -Verbose "Added request description '$incidentObject.RequestDescription' to request"
    }
    if($incidentObject.RequestShort){
        $requestObject += @{
            briefDescription = $incidentObject.RequestShort
        }
        Write-Verbose -Verbose "Added brief description '$incidentObject.RequestShort' request"
    }
       
    $request = $requestObject | ConvertTo-Json -Depth 10
    Write-Verbose -Verbose "Start creating ticket"
    try{
        Write-Verbose -Verbose "Starting to create TOPdesk incident '$incidentObject.RequestShort'"
        $response = Invoke-WebRequest -Uri $uriIncidents -Method POST -ContentType $contentType -Headers $headers -Body ([System.Text.Encoding]::UTF8.GetBytes($request)) -UseBasicParsing
        $incident = $response.Content | ConvertFrom-Json
        if($CloseTicket -eq "True"){
            Write-Verbose -Verbose "Successfully created TOPdesk incident '$incidentObject.RequestShort', immediately closed the ticket"
        }else{
            Write-Verbose -Verbose "Successfully created TOPdesk incident '$incidentObject.RequestShort'"
        }

    }catch{
        if($_.Exception.Message -eq "The remote server returned an error: (400) Bad Request."){
            $message  = ($_.ErrorDetails.Message | convertFrom-Json).message
            throw "Could not create incident, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message) $message"
        }else{
            throw "Could not create incident, errorcode: '0x$('{0:X8}' -f $_.Exception.HResult)', message: $($_.Exception.Message)"
        }
    }
    Write-Verbose -Verbose "Succesfully created TOPdesk incident  '$incidentObject.RequestShort' with number '$($incident.number)', check the Progress Log for details"

    return $incident
}

$incidentList = Get-Content -Raw -Path $path | ConvertFrom-Json
$incident = $incidentList | Where-Object { ($_.Identification.Id -eq $pRef.id) -and ($_.HelloIDAction -eq "Grant") } | Select-Object -Property * -ExcludeProperty DisplayName, Identification, HelloIDAction

if (-Not($dryRun -eq $False)) {
    if (![string]::IsNullOrEmpty($incident)) {
        try {
            $incidentResult = New-TopdeskIncident -incidentObject $incident

            $success = $True;
            $auditMessage = "Succesfully created TOPdesk incident with number $($incidentResult.number)"
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
	Success= $success;
    AccountReference= $aRef;
	AuditDetails=$auditMessage;
    Account= $account;
};

Write-Output $result | ConvertTo-Json -Depth 10;