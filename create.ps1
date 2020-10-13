#Initialize default properties
$success = $False;
$p = $person | ConvertFrom-Json
$auditMessage = " not created succesfully";

#TOPdesk system data
$url = 'https://customer-test.topdesk.net/tas/api'
$personUrl = $url + '/persons'

$apiKey = 'aaaaa-bbbbb-ccccc-ddddd-eeeee'
$userName = 'xyz'
$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json' }

#Connector settings
$createMissingDepartments = $True
$createMissingBudgetholders = $True

#mapping
$username = $p.Accounts.MicrosoftActiveDirectory.SamAccountName;
$email = $p.Accounts.MicrosoftActiveDirectory.Mail;

$account = @{
    surName = $p.Custom.TOPdeskSurName;
    firstName = $p.Name.NickName;
    firstInitials = $p.Name.Initials;
    gender = $p.Custom.TOPdeskGender;
    email = $email;
    jobTitle = $p.PrimaryContract.Title.Name;
    department = @{ id = $p.PrimaryContract.Department.DisplayName };
    budgetholder = @{ id = $p.PrimaryContract.CostCenter.code + " " + $P.PrimaryContract.CostCenter.Name };
    employeeNumber = $p.ExternalID;
    networkLoginName = $username;
    branch = @{ id = $p.PrimaryContract.Location.Name };
    tasLoginName = $username;
    isManager = $False;
    manager = @{ id = $p.PrimaryManager.ExternalId };
}

#correlation
$correlationField = 'employeeNumber';
$correlationValue = $p.ExternalID;

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
        $create = $False;
        $success = $True;
        $auditMessage = "Correlation found record $($correlationValue). Update succesful";
    }

    if($create){  
        $lookupFailure = $False
        
        # get branch
        write-verbose -verbose "Get branch"
        $branchUrl = $url + "/branches?query=name=='$($account.branch.id)'"
        $responseBranchJson = Invoke-WebRequest -uri $branchUrl -Method Get -Headers $headers -UseBasicParsing
        $personBranch = $responseBranchJson | ConvertFrom-Json
        
        if ([string]::IsNullOrEmpty($personBranch.id) -eq $True) {
            $auditMessage = $auditMessage + "; Branch '$($account.branch.id)' not found!"
            $lookupFailure = $True
        } else {
            $account.branch.id = $personBranch.id
        }
        
        # get department
        write-verbose -verbose "Get department"
        $departmentUrl = $url + "/departments"
        $responseDepartmentJson = Invoke-WebRequest -uri $departmentUrl -Method Get -Headers $headers -UseBasicParsing
        $responseDepartment = $responseDepartmentJson | ConvertFrom-Json
        $personDepartment = $responseDepartment | Where-object name -eq $account.department.id

        if ([string]::IsNullOrEmpty($personDepartment.id) -eq $True) {
            Write-Output -Verbose "Department '$($Account.department.id)' not found"
            if ($createMissingDepartments) {
                Write-Verbose -Verbose "Creating department '$($Account.department.id)' in TOPdesk"
                $bodyDepartment = @{ name=$Account.department.id } | ConvertTo-Json -Depth 1
                $responseDepartmentCreateJson = Invoke-WebRequest -uri $departmentUrl -Method POST -Headers $headers -Body $bodyDepartment -UseBasicParsing
                $responseDepartmentCreate = $responseDepartmentCreateJson | ConvertFrom-Json
                Write-Verbose -Verbose "Created department name '$($Account.department.id)' with id '$($responseDepartmentCreate.id)'"
                $account.department.id = $responseDepartmentCreate.id
            } else {
                $auditMessage = $auditMessage + "; Department '$($account.department.id)' not found"
                $lookupFailure = $True
            }
        } else {
            $account.department.id = $personDepartment.id
        }

        # get budgetHolder
        write-verbose -verbose "Get budgetHolder"
        $budgetHolderUrl = $url + "/budgetholders"
        $responseBudgetHolderJson = Invoke-WebRequest -uri $budgetHolderUrl -Method Get -Headers $headers -UseBasicParsing
        $responseBudgetHolder = $responseBudgetHolderJson | ConvertFrom-Json  
        $personBudgetholder = $responseBudgetHolder| Where-object name -eq $account.budgetHolder.id

        if ([string]::IsNullOrEmpty($personBudgetHolder.id) -eq $True) {
            Write-Verbose -Verbose "BudgetHolder '$($account.budgetHolder.id)' not found"
            if ($createMissingBudgetholders) {
                Write-Verbose -Verbose "Creating budgetHolder '$($Account.budgetHolder.id)' in TOPdesk"
                $bodyBudgetholder = @{ name=$Account.budgetHolder.id } | ConvertTo-Json -Depth 1
                $responseBudgetHolderCreateJson = Invoke-WebRequest -uri $budgetHolderUrl -Method POST -Headers $headers -Body $bodyBudgetHolder -UseBasicParsing
                $responseBudgetHolderCreate =  $responseBudgetHolderCreateJson | ConvertFrom-Json
                Write-Verbose -Verbose "Created budgetHolder name '$account.budgetHolder.id' with id: '$($responseBudgetHolderCreate.id)'"
                $account.budgetholder.id = $responseBudgetholderCreate.id
            } else {
                $auditMessage = $auditMessage + "; BudgetHolder '$($account.budgetHolder.id)' not found"
                $lookupFailure = $true
            }         
        } else {
            $account.budgetHolder.id = $personBudgetHolder.id
        }
        
        # get manager
        write-verbose -verbose "Get manager"
        $personManagerUrl = $personUrl + "/?page_size=2&query=$($correlationField)=='$($account.manager.id)'"
        $responseManagerJson = Invoke-WebRequest -uri $personManagerUrl -Method Get -Headers $headers -UseBasicParsing        
        $responseManager = $responseManagerJson | ConvertFrom-Json
        
        if ([string]::IsNullOrEmpty($responseManager.id) -eq $True) {
            $auditMessage = $auditMessage + "; Manager '$($account.manager.id)' not found"
            $lookupFailure = $true
        } else {
            $account.manager.id = $responseManager.id
            # set isManager if not configured
            if (!($responseManager.isManager)) {
                $managerUrl = $personUrl + "/id/" + $responseManager.id
                $bodyManagerEdit = '{"isManager": true }'
                $null = Invoke-WebRequest -uri $managerUrl -Method PATCH -Headers $headers -Body $bodyManagerEdit -UseBasicParsing
            }
        }
        
        if (!($lookupFailure)) {
            write-verbose -verbose "Creating account for '$($p.ExternalID)'"
            $bodyPersonCreate = $account | ConvertTo-Json -Depth 10
            $responsePersonCreate = Invoke-WebRequest -uri $personUrl -Method POST -Headers $headers -Body $bodyPersonCreate -UseBasicParsing
            $responsePersonCreateJson = $responsePersonCreate | ConvertFrom-Json
            if([string]::IsNullOrEmpty($responsePersonCreateJson.id)) {
                $aRef = $responsePersonCreateJson.id 
                $success = $True;
                $auditMessage = "created succesfully";
            }  
        } else {
            $success = $False;
        }
    }

    } catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden")
        {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
            $auditMessage = " not created succesfully: '$($_.Exception.Message)'";   
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'" 
            $auditMessage = " not created succesfully: '$($_.ErrorDetails.Message)'";  
        } else {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'" 
            $auditMessage = " not created succesfully: '$($_)'";  
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
};

Write-Output $result | ConvertTo-Json -Depth 10;