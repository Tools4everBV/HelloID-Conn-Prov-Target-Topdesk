#Initialize default properties
$success = $false
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$config = $configuration | ConvertFrom-Json
$auditMessage = " not disabled succesfully"

#TOPdesk system data
$url = $config.connection.url
$apiKey = $config.connection.apikey
$userName = $config.connection.username

$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json; charset=utf-8' }

#mapping
$username = ""
$email = ""

$account = @{
    email = $email
    networkLoginName = $username
    tasLoginName = $username
}

$PersonArchivingReason = @{
    id = "Persoon uit organisatie"
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-Not($dryRun -eq $true)){
    try {
        $lookupFailure = $false

        Write-Verbose -Verbose "Archiving reason lookup..."
        if ([string]::IsNullOrEmpty($PersonArchivingReason.id)) {
            $auditMessage = $auditMessage + "; Archiving reason is not set'"
            $lookupFailure = $true
            Write-Verbose -Verbose "Archiving reason lookup failed"
        } else {
            $archivingReasonUrl = $url + "/archiving-reasons"
            $responseArchivingReasonJson = Invoke-WebRequest -uri $archivingReasonUrl -Method Get -Headers $headers -UseBasicParsing
            $responseArchivingReason = $responseArchivingReasonJson.Content | Out-String | ConvertFrom-Json
            $archivingReason = $responseArchivingReason | Where-object name -eq $PersonArchivingReason.id

            if ([string]::IsNullOrEmpty($archivingReason.id) -eq $true) {
                Write-Verbose -Verbose "Archiving Reason '$($PersonArchivingReason.id)' not found"
                $auditMessage = $auditMessage + "; Archiving Reason '$($PersonArchivingReason.id)' not found"
                $lookupFailure = $true
                Write-Verbose -Verbose "Archiving Reason lookup failed"
            } else {
                $PersonArchivingReason.id = $archivingReason.id
                Write-Verbose -Verbose "Archiving Reason lookup succesful"
            }
        }

        Write-Verbose -Verbose "Person lookup..."
        $PersonUrl = $url + "/persons/id/${aRef}"
        $responsePersonJson = Invoke-WebRequest -uri $PersonUrl -Method Get -Headers $headers -UseBasicParsing
        $responsePerson = $responsePersonJson.Content | Out-String | ConvertFrom-Json

        if([string]::IsNullOrEmpty($responsePerson.id)) {
            $auditMessage = $auditMessage + "; Person is not found in TOPdesk'"
            $lookupFailure = $true
            Write-Verbose -Verbose "Person not found in TOPdesk"
        } else {
            Write-Verbose -Verbose "Person lookup succesful"
        }

        if (!($lookupFailure)) {
			Write-Verbose -Verbose "Updating account for '$($p.ExternalID)...'"
			$bodyPersonUpdate = $account | ConvertTo-Json -Depth 10
			$null = Invoke-WebRequest -uri $personUrl -Method PATCH -Headers $headers -Body  ([Text.Encoding]::UTF8.GetBytes($bodyPersonUpdate)) -UseBasicParsing
			Write-Verbose -Verbose "Updated account for '$($p.ExternalID)...'"

            if ($responsePerson.status -eq "person") {
                Write-Verbose -Verbose "Archiving account for '$($p.ExternalID)...'"
                $bodyPersonArchive = $PersonArchivingReason | ConvertTo-Json -Depth 10
                $archiveUrl = $url + "/persons/id/${aRef}/archive"
                $null = Invoke-WebRequest -uri $archiveUrl -Method PATCH -Body ([Text.Encoding]::UTF8.GetBytes($bodyPersonArchive)) -Headers $headers -UseBasicParsing
                Write-Verbose -Verbose "Account Archived"
                $auditMessage = "disabled succesfully"
            } else {
                Write-Verbose -Verbose "Person is already archived. Nothing to do"
            }
            $success = $true
            $auditMessage = "disabled succesfully"
        }

    } catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
            $auditMessage = " not disabled succesfully: '$($_.Exception.Message)'"
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'"
            $auditMessage = " not disabled succesfully: '$($_.ErrorDetails.Message)'"
        } else {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'"
            $auditMessage = " not disabled succesfully: '$($_)'"
        }
        $success = $false
    }
}

#build up result
$result = [PSCustomObject]@{
	Success = $success
	AuditDetails = $auditMessage
}

Write-Output $result | ConvertTo-Json -Depth 10
