#Initialize default properties
$success = $False
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
    id = "Persoon uit organisatie";
}

#Zet dit tijdelijk aan als het aanmaken van een ticket tijdelijk overgeslagen moet worden
#$dryRun = $True
#$success = $True

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
if(-Not($dryRun -eq $True)){
    try {
        $lookupFailure = $False

        write-verbose -verbose "Archiving reason lookup..."
        if ([string]::IsNullOrEmpty($PersonArchivingReason.id)) {
            $auditMessage = $auditMessage + "; Archiving reason is not set'"
            $lookupFailure = $True
            write-verbose -verbose "Archiving reason lookup failed"
        } else {
            $archivingReasonUrl = $url + "/archiving-reasons"
            $responseArchivingReasonJson = Invoke-WebRequest -uri $archivingReasonUrl -Method Get -Headers $headers -UseBasicParsing
            $responseArchivingReason = $responseArchivingReasonJson.Content | Out-String | ConvertFrom-Json
            $archivingReason = $responseArchivingReason | Where-object name -eq $PersonArchivingReason.id

            if ([string]::IsNullOrEmpty($archivingReason.id) -eq $True) {
                Write-Output -Verbose "Archiving Reason '$($PersonArchivingReason.id)' not found"
                $auditMessage = $auditMessage + "; Archiving Reason '$($PersonArchivingReason.id)' not found"
                $lookupFailure = $True
                write-verbose -verbose "Archiving Reason lookup failed"
            } else {
                $PersonArchivingReason.id = $archivingReason.id
                write-verbose -verbose "Archiving Reason lookup succesful"
            }
        }

        write-verbose -verbose "Person lookup..."
        $personUrl = $url + "/persons/id/${aRef}"
        $responsePersonJson = Invoke-WebRequest -uri $personUrl -Method Get -Headers $headers -UseBasicParsing
        $responsePerson = $responsePersonJson.Content | Out-String | ConvertFrom-Json

        if([string]::IsNullOrEmpty($responsePerson.id)) {
            $auditMessage = $auditMessage + "; Person is not found in TOPdesk'"
            $lookupFailure = $true
            write-verbose -verbose "Person not found in TOPdesk"
        } else {
            write-verbose -verbose "Person lookup succesful"
        }
           
        if (!($lookupFailure)) {
            if ($responsePerson.status -eq "person") {
                write-verbose -verbose "Archiving account for '$($p.ExternalID)...'"
                $bodyPersonArchive = $personArchivingReason | ConvertTo-Json -Depth 10
                $archiveUrl = $url + "/persons/id/${aRef}/archive"
                $null = Invoke-WebRequest -uri $archiveUrl -Method PATCH -Body ([Text.Encoding]::UTF8.GetBytes($bodyPersonArchive)) -Headers $headers -UseBasicParsing
                write-verbose -verbose "Account Archived"
            } else {
                write-verbose -verbose "Person is already archived. Nothing to do"
            }
            $success = $True
            $auditMessage = "deleted succesfully"
        }

    } catch {
        if ($_.Exception.Response.StatusCode -eq "Forbidden") {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
            $auditMessage = " not deleted succesfully: '$($_.Exception.Message)'" 
        } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'" 
            $auditMessage = " not deleted succesfully: '$($_.ErrorDetails.Message)'"
        } else {
            Write-Verbose -Verbose "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'"
            $auditMessage = " not deleted succesfully: '$($_)'"
        }        
        $success = $False
    }
}

#build up result
$result = [PSCustomObject]@{ 
	Success = $success;
	AuditDetails = $auditMessage;
}

Write-Output $result | ConvertTo-Json -Depth 10