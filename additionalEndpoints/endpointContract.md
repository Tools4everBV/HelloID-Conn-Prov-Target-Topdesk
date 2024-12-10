# Additional endpoint /contract

> [!IMPORTANT]
> We recommend using free fields in Topdesk, as these fields can be updated through the default `/person` endpoint. To do this, simply add `optionalFields1.text1` (for example) to your field mapping. Use the `/contract` endpoint only when the fields in the current `/person` endpoint are not sufficient or do not meet your requirements.

> [!TIP]
> [Topdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/)

> [!NOTE]
> Only `create` and `update` account lifecycle actions are supported. If updating a value in the `delete` script is required, use the `update` operations within the `delete` script. Ensure that you modify scripts only where field mappings are defined. This add-on requires at least one valid field containing `contract.` in the field mapping for proper functionality.

## fieldmapping
Add all required fields in de fieldmapping with the prefix `contract.`, example:
- contract.employmentTerminationDate
- contract.hireDate

For more options please look at [Topdesk API documentation /contract](https://developers.topdesk.com/explorer/?page=supporting-files#/Persons/getPersonContractByPersonId)

## splitting account and accountContract [Create / Update]
Because `/contract` is a different endpoint we need to split the fieldmapping data. Replace the `$account = $actionContext.Data` and `remove 'id'` part.

```powershell
#region Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
$account = [PSCustomObject]$actionContext.Data.PsObject.Copy()

# Remove ID field because only used for export data
if ($account.PSObject.Properties.Name -Contains 'id') {
	$account.PSObject.Properties.Remove('id')
}

# Remove properties contract.<x> because this is send to a different endpoint
if ($account.PSObject.Properties.Name -Contains 'contract') {
	$account.PSObject.Properties.Remove('contract')
}

$accountContract = [PSCustomObject]$actionContext.Data.contract.PsObject.Copy()
#endregion Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
```

## GET current contract data [Update]
We need to check if the current contract data on the Topdesk person needs to be updated. For this reason we first need to `GET` this data. Add this in the `#region lookup`

> [!TIP]
> Make sure output from your mapping is `null` or the same as HelloID receives the date/time fields this can be different based on how Powershell interprets the data. Most likely the example bellow works with the on-premise agent (`yyyy-MM-dd`)

```powershell
#region Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
$getContractSplatParams = @{
	Uri     = "$($actionContext.Configuration.baseUrl)/tas/api/persons/id/$($actionContext.References.Account)/contract"
	Method  = 'GET'
	Headers = $authHeaders
}
$TopdeskPersonContract = Invoke-TopdeskRestMethod @getContractSplatParams

# to return values to HelloID
$oldAccountContract = [PSCustomObject]@{}
$TopdeskPersonContract | Get-Member -MemberType Properties | ForEach-Object {
	$oldAccountContract | Add-Member -MemberType NoteProperty -Name $_.Name -Value $TopdeskPersonContract.$($_.Name)
}

# Response is yyyy-MM-ddT00:00:00.000+0000 and must be date only for the compare
if (-Not([string]::IsNullOrEmpty($TopdeskPersonContract.hireDate))) {
	# Extract the date part before 'T'
	$hireDate = $TopdeskPersonContract.hireDate -split 'T'
	$TopdeskPersonContract.hireDate = $hireDate[0]
}
if (-Not([string]::IsNullOrEmpty($TopdeskPersonContract.employmentTerminationDate))) {
	# Extract the date part before 'T'
	$terminationDate = $TopdeskPersonContract.employmentTerminationDate -split 'T'
	$TopdeskPersonContract.employmentTerminationDate = $terminationDate[0]
}
#endregion Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
```

## Enrich compare [Update]
Add all properties from contract `$accountContract` and `$TopdeskPersonContract` to `$accountDifferenceObject` and `$accountReferenceObject` to get a complete compare.
This must be added after `$accountDifferenceObject` and `$accountReferenceObject` are filled by `$account` and `$TopdeskPerson`.

```powershell
#region Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
$accountContract | Get-Member -MemberType Properties | ForEach-Object {
	$accountDifferenceObject | Add-Member -MemberType NoteProperty -Name "contract_$($_.Name)" -Value $accountContract.$($_.Name)
}
$TopdeskPersonContract | Get-Member -MemberType Properties | ForEach-Object {
	$accountReferenceObject | Add-Member -MemberType NoteProperty -Name "contract_$($_.Name)" -Value $TopdeskPersonContract.$($_.Name)
}
#endregion Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
```

## PATCH contract data [Create]
`PATCH` the contract data of the Topdesk person. Add this part after creating the Topdesk Person. Also `$outputContext.Data` and need to be filled correctly so custom events and audit logging will work correctly.

```powershell
#region Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
if (-Not($actionContext.DryRun -eq $true)) {
	$setContractSplatParams = @{
		Uri     = "$($actionContext.Configuration.baseUrl)/tas/api/persons/id/$($TopdeskPerson.id)/contract"
		Method  = 'PATCH'
		Headers = $authHeaders
		Body    = $AccountContract | ConvertTo-Json
	}
	$TopdeskPersonUpdatedContract = Invoke-TopdeskRestMethod @setContractSplatParams

	$newAccountContract = [PSCustomObject]@{}
	$TopdeskPersonUpdatedContract | Get-Member -MemberType Properties | ForEach-Object {
		$newAccountContract | Add-Member -MemberType NoteProperty -Name $_.Name -Value $TopdeskPersonUpdatedContract.$($_.Name)
	}
	$TopdeskPerson | Add-Member -MemberType NoteProperty -Name 'contract' -Value $newAccountContract
}
else {
	Write-Warning "DryRun would update Topdesk person contract [$($TopdeskPerson.id)]."
}
#endregion Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
```

## PATCH contract data [Update]
`PATCH` the contract data of the Topdesk person. Add this part after updating the Topdesk Person, before re-archiving in the update script. Also `$outputContext.Data` and `$outputContext.PreviousData` need to be filled correctly so custom events and audit logging will work correctly.

```powershell
#region Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
if (-Not($actionContext.DryRun -eq $true)) {
	$setContractSplatParams = @{
		Uri     = "$($actionContext.Configuration.baseUrl)/tas/api/persons/id/$($TopdeskPerson.id)/contract"
		Method  = 'PATCH'
		Headers = $authHeaders
		Body    = $AccountContract | ConvertTo-Json
	}
	$TopdeskPersonUpdatedContract = Invoke-TopdeskRestMethod @setContractSplatParams

	$newAccountContract = [PSCustomObject]@{}
	$TopdeskPersonUpdatedContract | Get-Member -MemberType Properties | ForEach-Object {
		$newAccountContract | Add-Member -MemberType NoteProperty -Name $_.Name -Value $TopdeskPersonUpdatedContract.$($_.Name)
	}
	$TopdeskPersonUpdated | Add-Member -MemberType NoteProperty -Name 'contract' -Value $newAccountContract
	$TopdeskPerson | Add-Member -MemberType NoteProperty -Name 'contract' -Value $oldAccountContract
}
else {
	Write-Warning "DryRun would update Topdesk person contract [$($TopdeskPerson.id)]."
}
#endregion Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
```