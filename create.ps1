#Initialize default properties
$success = $False
$p = $person | ConvertFrom-Json
$config = $configuration | ConvertFrom-Json 
$auditMessage = " not created succesfully"

#TOPdesk system data
$url = $config.connection.url
$apiKey = $config.connection.apikey
$userName = $config.connection.username

$personUrl = $url + '/persons'
$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json; charset=utf-8' }

#Connector settings
$createMissingDepartment = [Boolean]$config.persons.errorNoDepartmentHR
$errorOnMissingDepartment = [Boolean]$config.persons.errorNoDepartmentTD    # todo

$createMissingBudgetholder = [Boolean]$config.persons.errorNoBudgetHolderTD
$errorOnMissingBudgetholder = [Boolean]$config.persons.errorNoBudgetHolderHR # todo

$errorOnMissingManager = [Boolean]$config.persons.errorNoManagerHR

#mapping
$username = $p.Accounts.MicrosoftActiveDirectory.SamAccountName
$email = $p.Accounts.MicrosoftActiveDirectory.Mail

$account = @{
    surName = $p.Custom.TOPdeskSurName;
    firstName = $p.Name.NickName;
    firstInitials = $p.Name.Initials;
    gender = $p.Custom.TOPdeskGender;
    email = $email;
    jobTitle = $p.PrimaryContract.Title.Name;
    department = @{ id = $p.PrimaryContract.Team.Name };
    budgetHolder = @{ id = $p.PrimaryContract.CostCenter.code + " " + $P.PrimaryContract.CostCenter.Name };
    #budgetHolder = @{ id = "12345" + " " + "Tools4ever testnaam" };
    employeeNumber = $p.ExternalID;
    networkLoginName = $username;
    branch = @{ id = $p.PrimaryContract.Location.Name };
    tasLoginName = $username;
    isManager = $False;
    manager = @{ id = $p.PrimaryManager.ExternalId };
    showDepartment = $True;
}

#correlation
$correlationField = 'employeeNumber'
$correlationValue = $p.ExternalID
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-Not($dryRun -eq $True)) {
 try {
    $create = $True
    write-verbose -verbose "Correlate person"
    $personCorrelationUrl = $personUrl + "/?page_size=2&query=$($correlationField)=='$($correlationValue)'"
    $responseCorrelationJson = Invoke-WebRequest -uri $personCorrelationUrl -Method Get -Headers $headers -UseBasicParsing
    $responseCorrelation = $responseCorrelationJson | ConvertFrom-Json

    if(-Not($null -eq $responseCorrelation) -and -Not($null -eq $responseCorrelation[0].id)) {
        $aRef = $responseCorrelation[0].id 
        $create = $False
        $success = $True
        $auditMessage = "Correlation found record $($correlationValue). Update succesful"
        write-verbose -verbose "Person found in TOPdesk"
    }

    if($create){  
        write-verbose -verbose "Person not found in TOPdesk"
        $lookupFailure = $False
        
        # get branch
        write-verbose -verbose "Branch lookup..."
        if ([string]::IsNullOrEmpty($account.branch.id)) {
            $auditMessage = $auditMessage + "; Branch is empty for person '$($p.ExternalId)'"
            $lookupFailure = $True
            write-verbose -verbose "Branch lookup failed"
        } else {
            $branchUrl = $url + "/branches?query=name=='$($account.branch.id)'"
            $responseBranchJson = Invoke-WebRequest -uri $branchUrl -Method Get -Headers $headers -UseBasicParsing
            $personBranch = $responseBranchJson.Content | Out-String | ConvertFrom-Json
        
            if ([string]::IsNullOrEmpty($personBranch.id) -eq $True) {
                $auditMessage = $auditMessage + "; Branch '$($account.branch.id)' not found!"
                $lookupFailure = $True
                write-verbose -verbose "Branch lookup failed"
            } else {
                $account.branch.id = $personBranch.id
                write-verbose -verbose "Branch lookup succesful"
            }
        }
        
        # get department
        write-verbose -verbose "Department lookup..."
        if ([string]::IsNullOrEmpty($account.department.id)) {
            $auditMessage = $auditMessage + "; Department is empty for person '$($p.ExternalId)'"
            $lookupFailure = $True
            write-verbose -verbose "Department lookup failed"
        } else {
            $departmentUrl = $url + "/departments"
            $responseDepartmentJson = Invoke-WebRequest -uri $departmentUrl -Method Get -Headers $headers -UseBasicParsing
            $responseDepartment = $responseDepartmentJson.Content | Out-String | ConvertFrom-Json
            $personDepartment = $responseDepartment | Where-object name -eq $account.department.id

            if ([string]::IsNullOrEmpty($personDepartment.id) -eq $True) {
                Write-Output -Verbose "Department '$($account.department.id)' not found"
                if ($createMissingDepartment) {
                    Write-Verbose -Verbose "Creating department '$($account.department.id)' in TOPdesk"
                    $bodyDepartment = @{ name=$account.department.id } | ConvertTo-Json -Depth 1
                    $responseDepartmentCreateJson = Invoke-WebRequest -uri $departmentUrl -Method POST -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($bodyDepartment)) -UseBasicParsing
                    $responseDepartmentCreate = $responseDepartmentCreateJson.Content | Out-String | ConvertFrom-Json
                    Write-Verbose -Verbose "Created Department name '$($account.department.id)' with id '$($responseDepartmentCreate.id)'"
                    $account.department.id = $responseDepartmentCreate.id
                } else {
                    $auditMessage = $auditMessage + "; Department '$($account.department.id)' not found"
                    write-verbose -verbose "Department lookup failed"
                    $lookupFailure = $True
                }
            } else {
                $account.department.id = $personDepartment.id
                write-verbose -verbose "Department lookup succesful"
            }
        }

        # get budgetHolder
        write-verbose -verbose "BudgetHolder lookup..."
        if ([string]::IsNullOrEmpty($account.budgetHolder.id.replace(' ', '""')) -or $account.budgetHolder.id.StartsWith(' ') -or $account.budgetHolder.id.EndsWith(' ')) {
            $auditMessage = $auditMessage + "; BudgetHolder is empty for person '$($p.ExternalId)'. Removing budgetHolder from Account object..."
            $account.PSObject.Properties.Remove('budgetHolder')
			#$lookupFailure = $False
            #write-verbose -verbose "BudgetHolder lookup failed"
        } else {
            $budgetHolderUrl = $url + "/budgetholders"
            $responseBudgetHolderJson = Invoke-WebRequest -uri $budgetHolderUrl -Method Get -Headers $headers -UseBasicParsing
            $responseBudgetHolder = $responseBudgetHolderJson.Content | Out-String | ConvertFrom-Json
            $personBudgetholder = $responseBudgetHolder| Where-object name -eq $account.budgetHolder.id

            if ([string]::IsNullOrEmpty($personBudgetHolder.id) -eq $True) {
                Write-Verbose -Verbose "BudgetHolder '$($account.budgetHolder.id)' not found"
                if ($createMissingBudgetholder) {
                    Write-Verbose -Verbose "Creating budgetHolder '$($Account.budgetHolder.id)' in TOPdesk"
                    $bodyBudgetHolder = @{ name=$account.budgetHolder.id } | ConvertTo-Json -Depth 1
                    $responseBudgetHolderCreateJson = Invoke-WebRequest -uri $budgetHolderUrl -Method POST -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($bodyBudgetHolder)) -UseBasicParsing
                    $responseBudgetHolderCreate =  $responseBudgetHolderCreateJson.Content | Out-String | ConvertFrom-Json
                    Write-Verbose -Verbose "Created BudgetHolder name '$($account.budgetHolder.id)' with id: '$($responseBudgetHolderCreate.id)'"
                    $account.budgetHolder.id = $responseBudgetholderCreate.id
                } else {
                    $auditMessage = $auditMessage + "; BudgetHolder '$($account.budgetHolder.id)' not found"
                    $lookupFailure = $true
                    write-verbose -verbose "BudgetHolder lookup failed"
                }         
            } else {
                $account.budgetHolder.id = $personBudgetHolder.id
                write-verbose -verbose "BudgetHolder lookup succesful"
            }
        }
        
        # get manager
        write-verbose -verbose "Manager lookup..."
        if ([string]::IsNullOrEmpty($account.manager.id)) {
            $auditMessage = $auditMessage + "; Manager is empty for person '$($p.ExternalId)'"
            write-verbose -verbose "Manager lookup failed"
            if ($errorOnMissingManager) {
                $lookupFailure = $True
            }
        } else {
            $personManagerUrl = $personUrl + "/?page_size=2&query=$($correlationField)=='$($account.manager.id)'"
            $responseManagerJson = Invoke-WebRequest -uri $personManagerUrl -Method Get -Headers $headers -UseBasicParsing        
            $responseManager = $responseManagerJson.Content | Out-String | ConvertFrom-Json
            if ([string]::IsNullOrEmpty($responseManager.id) -eq $True) {
                $auditMessage = $auditMessage + "; Manager '$($account.manager.id)' not found"
                write-verbose -verbose "Manager lookup failed"
                if ($errorOnMissingManager) {
                    $lookupFailure = $True
                }
            } else {
                $account.manager.id = $responseManager.id
              
                # set isManager if not configured
                if (!($responseManager.isManager)) {
                    $managerUrl = $url + "/persons/id/" + $responseManager.id
                    $bodyManagerEdit = '{"isManager": true }'
                    $null = Invoke-WebRequest -uri $managerUrl -Method PATCH -Headers $headers -Body $bodyManagerEdit -UseBasicParsing
                }
                write-verbose -verbose "Manager lookup succesful"
            }
        }
               
        if (!($lookupFailure)) {
            write-verbose -verbose "Creating account for '$($p.ExternalID)'"
            $bodyPersonCreate = $account | ConvertTo-Json -Depth 10
            $responsePersonCreate = Invoke-WebRequest -uri $personUrl -Method POST -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($bodyPersonCreate)) -UseBasicParsing
            $responsePersonCreateJson = $responsePersonCreate.Content | Out-String | ConvertFrom-Json
            if(![string]::IsNullOrEmpty($responsePersonCreateJson.id)) {
                $aRef = $responsePersonCreateJson.id
                $success = $True
                $auditMessage = "created succesfully"
            }  
        } else {
            $success = $False
        }
    }

    } catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
            $auditMessage = " not created succesfully: '$($_.Exception.Message)'" 
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'" 
            $auditMessage = " not created succesfully: '$($_.ErrorDetails.Message)'"
        } else {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'" 
            $auditMessage = " not created succesfully: '$($_)'" 
        }        
        $success = $False
    }
}

#build up result
$result = [PSCustomObject]@{ 
	Success= $success;
    AccountReference=$aRef;
	AuditDetails=$auditMessage;
    Account=$account;
}

Write-Output $result | ConvertTo-Json -Depth 10