#Initialize default properties
$success = $false
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
$createMissingDepartment = [System.Convert]::ToBoolean($config.persons.errorNoDepartmentTD)
$errorOnMissingDepartment = [System.Convert]::ToBoolean($config.persons.errorNoDepartmentHR)

$createMissingBudgetholder = [System.Convert]::ToBoolean($config.persons.errorNoBudgetHolderTD)
$errorOnMissingBudgetholder = [System.Convert]::ToBoolean($config.persons.errorNoBudgetHolderHR)

$errorOnMissingManager = [System.Convert]::ToBoolean($config.persons.errorNoManagerHR)

#mapping
$username = $p.Accounts.MicrosoftActiveDirectory.SamAccountName
$email = $p.Accounts.MicrosoftActiveDirectory.Mail
$surname = ""

$prefix = ""
if(-Not([string]::IsNullOrEmpty($p.Name.FamilyNamePrefix))) {
    $prefix = $p.Name.FamilyNamePrefix + " "
}

$partnerprefix = ""
if(-Not([string]::IsNullOrEmpty($p.Name.FamilyNamePartnerPrefix))) {
    $partnerprefix = $p.Name.FamilyNamePartnerPrefix + " "
}

switch($p.Name.Convention) {
    "B" {$surname += $prefix + $p.Name.FamilyName}
    "P" {$surname += $partnerprefix + $p.Name.FamilyNamePartner}
    "BP" {$surname += $prefix + $p.Name.FamilyName + " - " + $partnerprefix + $p.Name.FamilyNamePartner}
    "PB" {$surname += $partnerprefix + $p.Name.FamilyNamePartner + " - " + $prefix + $p.Name.FamilyName}
    default {$surname += $prefix + $p.Name.FamilyName}
}

# In some configurations this is in dutch (Man/Vrouw)
switch($p.details.Gender) {
    "M" {$gender = "MALE"}
    "V" {$gender = "FEMALE"}
    default {$gender = ""}
}

$account = @{
    surName = $surname
    firstName = $p.Name.NickName
    firstInitials = $p.Name.Initials
    #gender = $gender
    email = $email
    jobTitle = $p.PrimaryContract.Title.Name
    department = @{ id = $p.PrimaryContract.Department.DisplayName }
	#personExtraFieldA = @{ id = "Value for PersonExtraFieldA"}
    #budgetHolder = @{ id = $p.PrimaryContract.CostCenter.code + " " + $P.PrimaryContract.CostCenter.Name }
    employeeNumber = $p.ExternalID
    networkLoginName = $username
    branch = @{ id = "Fixed Branch" }
    tasLoginName = $username
    isManager = $false
    manager = @{ id = $p.PrimaryManager.ExternalId }
    showDepartment = $true
}

#correlation
$correlationField = 'employeeNumber'
$correlationValue = $p.ExternalID

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-Not($dryRun -eq $true)) {
    try {
        $create = $true
        Write-Verbose -Verbose -Message "Correlate person"
        $personCorrelationUrl = $personUrl + "/?page_size=2&query=$($correlationField)=='$($correlationValue)'"
        $responseCorrelationJson = Invoke-WebRequest -uri $personCorrelationUrl -Method Get -Headers $headers -UseBasicParsing
        $responseCorrelation = $responseCorrelationJson | ConvertFrom-Json

        if(-Not($null -eq $responseCorrelation) -and -Not($null -eq $responseCorrelation[0].id)) {
            $aRef = $responseCorrelation[0].id
            $create = $false
            $success = $true
            $auditMessage = "Correlation found record $($correlationValue). Update succesful"
            Write-Verbose -Verbose -Message "Person found in TOPdesk"
        }

        if($create){
            Write-Verbose -Verbose -Message "Person not found in TOPdesk"
            $lookupFailure = $false

            # get branch
            Write-Verbose -Verbose -Message "Branch lookup..."
            if ([string]::IsNullOrEmpty($account.branch.id)) {
                $auditMessage = $auditMessage + "; Branch is empty for person '$($p.ExternalId)'"
                $lookupFailure = $true
                Write-Verbose -Verbose -Message "Branch lookup failed"
            } else {
                $branchUrl = $url + "/branches"
                $responseBranchJson = Invoke-WebRequest -uri $branchUrl -Method Get -Headers $headers -UseBasicParsing
                $responseBranch = $responseBranchJson.Content | Out-String | ConvertFrom-Json
                $personBranch = $responseBranch | Where-object name -eq $account.branch.id

                if ([string]::IsNullOrEmpty($personBranch.id) -eq $true) {
                    $auditMessage = $auditMessage + "; Branch '$($account.branch.id)' not found!"
                    $lookupFailure = $true
                    Write-Verbose -Verbose -Message "Branch lookup failed"
                } else {
                    $account.branch.id = $personBranch.id
                    Write-Verbose -Verbose -Message "Branch lookup succesful"
                }
            }

            # get department
            Write-Verbose -Verbose -Message "Department lookup..."
            if ([string]::IsNullOrEmpty($account.department.id)) {
                $auditMessage = $auditMessage + "; Department is empty for person '$($p.ExternalId)'"
                $lookupFailure = $true
                Write-Verbose -Verbose -Message "Department lookup failed"
            } else {
                $departmentUrl = $url + "/departments"
                $responseDepartmentJson = Invoke-WebRequest -uri $departmentUrl -Method Get -Headers $headers -UseBasicParsing
                $responseDepartment = $responseDepartmentJson.Content | Out-String | ConvertFrom-Json
                $personDepartment = $responseDepartment | Where-object name -eq $account.department.id

                if ([string]::IsNullOrEmpty($personDepartment.id) -eq $true) {
                    Write-Verbose -Verbose -Message "Department '$($account.department.id)' not found"
                    if ($createMissingDepartment) {
                        Write-Verbose -Verbose -Message "Creating department '$($account.department.id)' in TOPdesk"
                        $bodyDepartment = @{ name=$account.department.id } | ConvertTo-Json -Depth 1
                        $responseDepartmentCreateJson = Invoke-WebRequest -uri $departmentUrl -Method POST -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($bodyDepartment)) -UseBasicParsing
                        $responseDepartmentCreate = $responseDepartmentCreateJson.Content | Out-String | ConvertFrom-Json
                        Write-Verbose -Verbose -Message "Created Department name '$($account.department.id)' with id '$($responseDepartmentCreate.id)'"
                        $account.department.id = $responseDepartmentCreate.id
                    } else {
                        $auditMessage = $auditMessage + "; Department '$($account.department.id)' not found"
                        Write-Verbose -Verbose -Message "Department lookup failed"
                        if ($errorOnMissingDepartment) {
                            $lookupFailure = $true
                        }
                    }
                } else {
                    $account.department.id = $personDepartment.id
                    Write-Verbose -Verbose -Message "Department lookup succesful"
                }
            }

            # get budgetHolder
            Write-Verbose -Verbose -Message "BudgetHolder lookup..."
            if ([string]::IsNullOrEmpty($account.budgetHolder) -or [string]::IsNullOrEmpty($account.budgetHolder.id.replace(' ', '""')) -or $account.budgetHolder.id.StartsWith(' ') -or $account.budgetHolder.id.EndsWith(' ')) {
                $auditMessage = $auditMessage + "; BudgetHolder is empty for person '$($p.ExternalId)'. Removing budgetHolder from Account object..."
                $account.PSObject.Properties.Remove('budgetHolder')
                #$lookupFailure = $false
                #Write-Verbose -Verbose -Message "BudgetHolder lookup failed"
            } else {
                $budgetHolderUrl = $url + "/budgetholders"
                $responseBudgetHolderJson = Invoke-WebRequest -uri $budgetHolderUrl -Method Get -Headers $headers -UseBasicParsing
                $responseBudgetHolder = $responseBudgetHolderJson.Content | Out-String | ConvertFrom-Json
                $personBudgetholder = $responseBudgetHolder| Where-object name -eq $account.budgetHolder.id

                if ([string]::IsNullOrEmpty($personBudgetHolder.id) -eq $true) {
                    Write-Verbose -Verbose -Message "BudgetHolder '$($account.budgetHolder.id)' not found"
                    if ($createMissingBudgetholder) {
                        Write-Verbose -Verbose -Message "Creating budgetHolder '$($Account.budgetHolder.id)' in TOPdesk"
                        $bodyBudgetHolder = @{ name=$account.budgetHolder.id } | ConvertTo-Json -Depth 1
                        $responseBudgetHolderCreateJson = Invoke-WebRequest -uri $budgetHolderUrl -Method POST -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($bodyBudgetHolder)) -UseBasicParsing
                        $responseBudgetHolderCreate =  $responseBudgetHolderCreateJson.Content | Out-String | ConvertFrom-Json
                        Write-Verbose -Verbose -Message "Created BudgetHolder name '$($account.budgetHolder.id)' with id: '$($responseBudgetHolderCreate.id)'"
                        $account.budgetHolder.id = $responseBudgetholderCreate.id
                    } else {
                        $auditMessage = $auditMessage + "; BudgetHolder '$($account.budgetHolder.id)' not found"
                        if ($errorOnMissingBudgetholder) {
                            $lookupFailure = $true
                        }
                        Write-Verbose -Verbose -Message "BudgetHolder lookup failed"
                    }
                } else {
                    $account.budgetHolder.id = $personBudgetHolder.id
                    Write-Verbose -Verbose -Message "BudgetHolder lookup succesful"
                }
            }

            # get personExtraFieldA
            Write-Verbose -Verbose -Message "personExtraFieldA lookup..."
            if ([string]::IsNullOrEmpty($account.personExtraFieldA) -or [string]::IsNullOrEmpty($account.personExtraFieldA.id.replace(' ', '""')) -or $account.personExtraFieldA.id.StartsWith(' ') -or $account.personExtraFieldA.id.EndsWith(' ')) {
                $auditMessage = $auditMessage + "; personExtraFieldA is empty for person '$($p.ExternalId)'. Removing personExtraFieldA from Account object..."
                Write-Verbose -Verbose -Message -Message "personExtraFieldA is empty for person '$($p.ExternalId)'. Removing personExtraFieldA from Account object..."
                $account.PSObject.Properties.Remove('personExtraFieldA')
            } else {
                $personExtraFieldAUrl = $url + "/personExtraFieldAEntries"
                $responsepersonExtraFieldAJson = Invoke-WebRequest -uri $personExtraFieldAUrl -Method Get -Headers $headers -UseBasicParsing
                $responsepersonExtraFieldA = $responsepersonExtraFieldAJson.Content | Out-String | ConvertFrom-Json
                $personpersonExtraFieldA = $responsepersonExtraFieldA | Where-object name -eq $account.personExtraFieldA.id

                if ([string]::IsNullOrEmpty($personpersonExtraFieldA.id) -eq $true) {
                    Write-Verbose -Verbose -Message "personExtraFieldA '$($account.personExtraFieldA.id)' not found"

                    $auditMessage = $auditMessage + "; personExtraFieldA '$($account.personExtraFieldA.id)' not found"
                    if ($errorOnMissingpersonExtraFieldA) {
                        $lookupFailure = $true
                    }
                    Write-Verbose -Verbose -Message "personExtraFieldA lookup failed"

                } else {
                    $account.personExtraFieldA.id = $personpersonExtraFieldA.id
                    Write-Verbose -Verbose -Message "personExtraFieldA lookup succesful"
                }
            }

            # get manager
            Write-Verbose -Verbose -Message "Manager lookup..."
            if ([string]::IsNullOrEmpty($account.manager.id)) {
                $auditMessage = $auditMessage + "; Manager is empty for person '$($p.ExternalId)'"
                Write-Verbose -Verbose -Message "Manager lookup failed"
                if ($errorOnMissingManager) {
                    $lookupFailure = $true
                }
            } else {
                $personManagerUrl = $personUrl + "/?page_size=2&query=$($correlationField)=='$($account.manager.id)'"
                $responseManagerJson = Invoke-WebRequest -uri $personManagerUrl -Method Get -Headers $headers -UseBasicParsing
                $responseManager = $responseManagerJson.Content | Out-String | ConvertFrom-Json
                if ([string]::IsNullOrEmpty($responseManager.id) -eq $true) {
                    $auditMessage = $auditMessage + "; Manager '$($account.manager.id)' not found"
                    Write-Verbose -Verbose -Message "Manager lookup failed"
                    if ($errorOnMissingManager) {
                        $lookupFailure = $true
                    }
                } else {
                    $account.manager.id = $responseManager.id

                    # set isManager if not configured
                    if (!($responseManager.isManager)) {
                        $managerUrl = $url + "/persons/id/" + $responseManager.id
                        $bodyManagerEdit = '{"isManager": true }'
                        $null = Invoke-WebRequest -uri $managerUrl -Method PATCH -Headers $headers -Body $bodyManagerEdit -UseBasicParsing
                    }
                    Write-Verbose -Verbose -Message "Manager lookup succesful"
                }
            }

            if (!($lookupFailure)) {
                Write-Verbose -Verbose -Message "Creating account for '$($p.ExternalID)'"
                $bodyPersonCreate = $account | ConvertTo-Json -Depth 10
                $responsePersonCreate = Invoke-WebRequest -uri $personUrl -Method POST -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($bodyPersonCreate)) -UseBasicParsing
                $responsePersonCreateJson = $responsePersonCreate.Content | Out-String | ConvertFrom-Json
                if(![string]::IsNullOrEmpty($responsePersonCreateJson.id)) {
                    $aRef = $responsePersonCreateJson.id
                    $success = $true
                    $auditMessage = "created succesfully"
                }
            } else {
                $success = $false
            }
        }

    } catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            Write-Verbose -Verbose -Message "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
            $auditMessage = " not created succesfully: '$($_.Exception.Message)'"
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            Write-Verbose -Verbose -Message "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'"
            $auditMessage = " not created succesfully: '$($_.ErrorDetails.Message)'"
        } else {
            Write-Verbose -Verbose -Message "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'"
            $auditMessage = " not created succesfully: '$($_)'"
        }
        $success = $false
    }
}

#build up result
$result = [PSCustomObject]@{
	Success= $success
    AccountReference=$aRef
	AuditDetails=$auditMessage
    Account=$account
}

Write-Output $result | ConvertTo-Json -Depth 10