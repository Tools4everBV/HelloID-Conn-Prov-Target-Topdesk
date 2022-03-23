# This script can be used to fill the employeeNumber field in TOPdesk.

# The two Csvs are created in the IAM Vault Browser.
# Persons.csv = class identities
# Topdesk.csv = class TopdeskPersons

#load csvs
$personsHr = Import-Csv .\persons.csv
$personsTopdesk = Import-Csv .\topdesk.csv

#group persons on search key
$personsHrGrouped = $personsHr | Group-Object "email.business" -AsHashTable

#Setup headers voor TD connection
$username = "xxxxxxx"
$apiKey = "xxxxxxx"
$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json; charset=utf-8' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#Loop through every person record
ForEach ($person in $personsTopdesk) {
    if ($person.status -eq "person")   {
        if (![string]::IsNullOrEmpty($person.email)) {
            $personHr = $personsHrGrouped[$person.email]
            $account = @{
                employeeNumber =  $personHr.employeeId
            }

            try {
                $PersonUrl = "https://customer-test.topdesk.net/tas/api/persons/id/$($person.id)"
                $bodyPersonUpdate = $account | ConvertTo-Json -Depth 10
                $null = Invoke-WebRequest -uri $personUrl -Method PATCH -Headers $headers -Body  ([Text.Encoding]::UTF8.GetBytes($bodyPersonUpdate)) -UseBasicParsing
            } catch {
                if ($_.Exception.Response.StatusCode -eq "Forbidden") {
                    Write-Error "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.Exception.Message)'"
                    $_
                } elseif (![string]::IsNullOrEmpty($_.ErrorDetails.Message)) {
                    Write-Error  "Something went wrong $($_.ScriptStackTrace). Error message: '$($_.ErrorDetails.Message)'"
                    $_
                } else {
                    Write-Error "Something went wrong $($_.ScriptStackTrace). Error message: '$($_)'"
                }
            }
        } else {
            Write-Error  "Emailadress is empty for person"
            Write-Error $person | ConvertTo-Json
        }
    } else {
        Write-Error  "Person is archived"
        Write-Error $person | ConvertTo-Json
    }
}
