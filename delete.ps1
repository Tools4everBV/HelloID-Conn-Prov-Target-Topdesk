#Initialize default properties
$success = $false
$p = $person | ConvertFrom-Json
$aRef = $accountReference | ConvertFrom-Json
$config = $configuration | ConvertFrom-Json
$auditMessage = " not deleted succesfully"

#TOPdesk system data
$url = $config.connection.url
$apiKey = $config.connection.apikey
$userName = $config.connection.username

$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json; charset=utf-8' }

$PersonArchivingReason = @{
    id = "Persoon uit organisatie"
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-Not($dryRun -eq $true)){
    try {
        $lookupFailure = $false

        Write-Verbose -Verbose -Message  "Archiving reason lookup..."
        if ([string]::IsNullOrEmpty($PersonArchivingReason.id)) {
            $auditMessage = $auditMessage + "; Archiving reason is not set'"
            $lookupFailure = $true
            Write-Verbose -Verbose -Message  "Archiving reason lookup failed"
        } else {
            $archivingReasonUrl = $url + "/archiving-reasons"
            $responseArchivingReasonJson = Invoke-WebRequest -uri $archivingReasonUrl -Method Get -Headers $headers -UseBasicParsing
            $responseArchivingReason = $responseArchivingReasonJson.Content | Out-String | ConvertFrom-Json
            $archivingReason = $responseArchivingReason | Where-object name -eq $PersonArchivingReason.id

            if ([string]::IsNullOrEmpty($archivingReason.id) -eq $true) {
                Write-Verbose -Verbose -Message  -Message "Archiving Reason '$($PersonArchivingReason.id)' not found"
                $auditMessage = $auditMessage + "; Archiving Reason '$($PersonArchivingReason.id)' not found"
                $lookupFailure = $true
                Write-Verbose -Verbose -Message  "Archiving Reason lookup failed"
            } else {
                $PersonArchivingReason.id = $archivingReason.id
                Write-Verbose -Verbose -Message  "Archiving Reason lookup succesful"
            }
        }

        Write-Verbose -Verbose -Message  "Person lookup..."
        $personUrl = $url + "/persons/id/${aRef}"
        $responsePersonJson = Invoke-WebRequest -uri $personUrl -Method Get -Headers $headers -UseBasicParsing
        $responsePerson = $responsePersonJson.Content | Out-String | ConvertFrom-Json

        if([string]::IsNullOrEmpty($responsePerson.id)) {
            $auditMessage = $auditMessage + "; Person is not found in TOPdesk'"
            $lookupFailure = $true
            Write-Verbose -Verbose -Message  "Person not found in TOPdesk"
        } else {
            Write-Verbose -Verbose -Message  "Person lookup succesful"
        }

        if (!($lookupFailure)) {
            if ($responsePerson.status -eq "person") {
                Write-Verbose -Verbose -Message  "Archiving account for '$($p.ExternalID)...'"
                $bodyPersonArchive = $personArchivingReason | ConvertTo-Json -Depth 10
                $archiveUrl = $url + "/persons/id/${aRef}/archive"
                $null = Invoke-WebRequest -uri $archiveUrl -Method PATCH -Body ([Text.Encoding]::UTF8.GetBytes($bodyPersonArchive)) -Headers $headers -UseBasicParsing
                Write-Verbose -Verbose -Message  "Account Archived"
            } else {
                Write-Verbose -Verbose -Message  "Person is already archived. Nothing to do"
            }
            $success = $true
            $auditMessage = "deleted succesfully"
        }

    } catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            Write-Verbose -Verbose -Message  "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
            $auditMessage = " not deleted succesfully: '$($_.Exception.Message)'"
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            Write-Verbose -Verbose -Message  "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'"
            $auditMessage = " not deleted succesfully: '$($_.ErrorDetails.Message)'"
        } else {
            Write-Verbose -Verbose -Message  "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'"
            $auditMessage = " not deleted succesfully: '$($_)'"
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