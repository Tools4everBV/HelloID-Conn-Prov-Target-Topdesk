## Correlation Report by externalId
## The purpose of this script is to pull in Source Data and check if we can link
## existing accounts by id. It will then report any accounts/persons
## that match up, need to be created, or we have multiple matches for.

## Instructions
## 1. Update Topdesk API Setings
## 2. Add Source Data logic
## 3. Update Request Query to select the proper ID field
## 3a. If ID field is changed update $result ID field as well.

#Settings
#Topdesk
$url 		= 'https://[customer].topdesk.net/tas/api'
$apiKey 	= '[api_key]'
$userName 	= '[username]'
#correlation field Topdesk
$correlationField = 'employeeNumber'
#correlation field source is by default ExternalId

#Source Data
Write-Information "Retrieving Source data";
 
# need list of all persons for correlation
$sourcePersons = [System.Collections.ArrayList]::new()
# get the source persons 
# [logic for retrieving persons]

$persons = $sourcePersons
Write-Information "$($persons.count) source record(s)";

#Topdesk
#Authorization
$personUrl = $url + '/persons'
$bytes = [System.Text.Encoding]::ASCII.GetBytes("${userName}:${apiKey}")
$base64 = [System.Convert]::ToBase64String($bytes)
$headers = @{ Authorization = "BASIC $base64"; Accept = 'application/json'; "Content-Type" = 'application/json; charset=utf-8' }
    
#Compare
$results = @{
    create = [System.Collections.ArrayList]@();
    match = [System.Collections.ArrayList]@();
}

$i = 1;
foreach($person in $persons) {
    Write-Information "$($i):$($persons.count)";
    $result = $null

    #Check if account exists (externalId), else create
    $personCorrelationUrl = $personUrl + "/?page_size=2&query=$($correlationField)=='$($person.ExternalId)'" # Change this if the source correlation field is different from ExternalId
    $responseCorrelationJson = Invoke-WebRequest -uri $personCorrelationUrl -Method Get -Headers $headers -UseBasicParsing
    $responseCorrelation = $responseCorrelationJson | ConvertFrom-Json

    foreach($r in $responseCorrelation) {
        $result = [PSCustomObject]@{ id = $person.externalid; email = $r.email; userId = $r.tasLoginName; person = $person; tdUser = $r; } # Change $person.externalId if source correlation field is changed
        [void]$results.match.Add($result);
    }

    if($null -eq $responseCorrelation) { [void]$results.create.Add($person) }
    $i++;
}

#Duplicate Correlations
$duplicates = [System.Collections.ArrayList]@();
$duplicatesbyUserId = ($results.match | Group-Object -Property userId) | Where-Object { $_.Count -gt 1 }
if($duplicatesbyUserId -is [System.Array]) { [void]$duplicates.AddRange($duplicatesbyUserId) } else { [void]$duplicates.Add($duplicatesbyUserId) };
$duplicatesbyId = ($results.match | Group-Object -Property Id) | Where-Object { $_.Count -gt 1 }
if($duplicatesbyId -is [System.Array]) { [void]$duplicates.AddRange($duplicatesbyId) } else { [void]$duplicates.Add($duplicatesbyId) };

#Results
Write-Information "$($results.create.count) Create(s)"
Write-Information "$($results.match.count) Correlation(s)"
Write-Information "$($duplicates.count) Duplicate Correlation(s)"

if($results.create.count -gt 0) { $results.create | Out-GridView }
if($duplicates.count -gt 0) { $duplicates | Out-GridView }
if($results.match.count -gt 0) { $results.match | Out-GridView }