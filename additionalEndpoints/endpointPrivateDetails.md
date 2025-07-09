# Additional endpoint /privateDetails

> [!IMPORTANT]
> We recommend using free fields in Topdesk, as these fields can be updated through the default `/person` endpoint. To do this, simply add `optionalFields1.text1` (for example) to your field mapping. Use the `/privateDetails` endpoint only when the fields in the current `/person` endpoint are not sufficient or do not meet your requirements.

> [!TIP]
> [Topdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/)

> [!NOTE]
> > Only `create`, `update` and `delete` account lifecycle actions are supported. Ensure that you modify scripts only where field mappings are defined. This add-on requires at least one valid field containing `privateDetails.` in the field mapping for proper functionality.

## Additional permissions

| Permission              | Read | Write | Create | Archive |
| ----------------------- | ---- | ----- | ------ | ------- |
| <b>Supporting Files</b> |
| Person private tab      | x    | x     |        |         |

## fieldmapping
Add all required fields in de fieldmapping with the prefix `privateDetails.`, example:
- privateDetails.privateEmail

For more options please look at [Topdesk API documentation /privateDetails](https://developers.topdesk.com/explorer/?page=supporting-files#/Persons/getPersonPrivateDetailsByPersonId)

## splitting account and accountPrivateDetails [Create / Update / Delete]
Because `/privateDetails` is a different endpoint we need to split the fieldmapping data. Replace the `$account = $actionContext.Data` and `remove 'id'` part.

```powershell
#region Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
$account = [PSCustomObject]$actionContext.Data.PsObject.Copy()

# Remove ID field because only used for export data
if ($account.PSObject.Properties.Name -Contains 'id') {
	$account.PSObject.Properties.Remove('id')
}

# Remove properties privateDetails.<x> because this is send to a different endpoint
if ($account.PSObject.Properties.Name -Contains 'privateDetails') {
	$account.PSObject.Properties.Remove('privateDetails')
}

$accountPrivateDetails = [PSCustomObject]$actionContext.Data.privateDetails.PsObject.Copy()
#endregion Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
```

## GET current privateDetails data [Update / Delete]
We need to check if the current privateDetails data on the Topdesk person needs to be updated. For this reason we first need to `GET` this data. Add this in the `#region lookup`

```powershell
#region Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
$getPrivateDetailsSplatParams = @{
	Uri     = "$($actionContext.Configuration.baseUrl)/tas/api/persons/id/$($actionContext.References.Account)/privateDetails"
	Method  = 'GET'
	Headers = $authHeaders
}
$TopdeskPersonPrivateDetails = Invoke-TopdeskRestMethod @getPrivateDetailsSplatParams

# to return values to HelloID
$oldAccountPrivateDetails = [PSCustomObject]@{}
$TopdeskPersonPrivateDetails | Get-Member -MemberType Properties | ForEach-Object {
	$oldAccountPrivateDetails | Add-Member -MemberType NoteProperty -Name $_.Name -Value $TopdeskPersonPrivateDetails.$($_.Name)
}
#endregion Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
```

## Enrich compare [Update / Delete]
Add all properties from privateDetails `$accountPrivateDetails` and `$TopdeskPersonPrivateDetails` to `$accountDifferenceObject` and `$accountReferenceObject` to get a complete compare.
This must be added after `$accountDifferenceObject` and `$accountReferenceObject` are filled by `$account` and `$TopdeskPerson`.

```powershell
#region Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
$accountPrivateDetails | Get-Member -MemberType Properties | ForEach-Object {
	$accountDifferenceObject | Add-Member -MemberType NoteProperty -Name "privateDetails_$($_.Name)" -Value $accountPrivateDetails.$($_.Name)
}
$TopdeskPersonPrivateDetails | Get-Member -MemberType Properties | ForEach-Object {
	$accountReferenceObject | Add-Member -MemberType NoteProperty -Name "privateDetails_$($_.Name)" -Value $TopdeskPersonPrivateDetails.$($_.Name)
}
#endregion Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
```

## PATCH privateDetails data [Create]
`PATCH` the privateDetails data of the Topdesk person. Add this part after creating the Topdesk Person. Also `$outputContext.Data` and need to be filled correctly so custom events and audit logging will work correctly.

```powershell
#region Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
if (-Not($actionContext.DryRun -eq $true)) {
	$setPrivateDetailsSplatParams = @{
		Uri     = "$($actionContext.Configuration.baseUrl)/tas/api/persons/id/$($TopdeskPerson.id)/privateDetails"
		Method  = 'PATCH'
		Headers = $authHeaders
		Body    = $accountPrivateDetails | ConvertTo-Json
	}
	$TopdeskPersonUpdatedPrivateDetails = Invoke-TopdeskRestMethod @setPrivateDetailsSplatParams

	$newAccountPrivateDetails = [PSCustomObject]@{}
	$TopdeskPersonUpdatedPrivateDetails | Get-Member -MemberType Properties | ForEach-Object {
		$newAccountPrivateDetails | Add-Member -MemberType NoteProperty -Name $_.Name -Value $TopdeskPersonUpdatedPrivateDetails.$($_.Name)
	}
	$TopdeskPerson | Add-Member -MemberType NoteProperty -Name 'privateDetails' -Value $newAccountPrivateDetails
}
else {
	Write-Warning "DryRun would update Topdesk person privateDetails [$($TopdeskPerson.id)]."
}
#endregion Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
```

## PATCH privateDetails data [Update / Delete]
`PATCH` the privateDetails data of the Topdesk person. Add this part after updating the Topdesk Person, before re-archiving in the update script. Also `$outputContext.Data` and need to be filled correctly so custom events and audit logging will work correctly.

```powershell
#region Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
if (-Not($actionContext.DryRun -eq $true)) {
	$setPrivateDetailsSplatParams = @{
		Uri     = "$($actionContext.Configuration.baseUrl)/tas/api/persons/id/$($TopdeskPerson.id)/privateDetails"
		Method  = 'PATCH'
		Headers = $authHeaders
		Body    = $accountPrivateDetails | ConvertTo-Json
	}
	$TopdeskPersonUpdatedPrivateDetails = Invoke-TopdeskRestMethod @setPrivateDetailsSplatParams

	$newAccountPrivateDetails = [PSCustomObject]@{}
	$TopdeskPersonUpdatedPrivateDetails | Get-Member -MemberType Properties | ForEach-Object {
		$newAccountPrivateDetails | Add-Member -MemberType NoteProperty -Name $_.Name -Value $TopdeskPersonUpdatedPrivateDetails.$($_.Name)
	}
	$TopdeskPersonUpdated | Add-Member -MemberType NoteProperty -Name 'privateDetails' -Value $newAccountPrivateDetails
	$TopdeskPerson | Add-Member -MemberType NoteProperty -Name 'privateDetails' -Value $oldAccountPrivateDetails
}
else {
	Write-Warning "DryRun would update Topdesk person privateDetails [$($TopdeskPerson.id)]."
}
#endregion Custom - <yyyy-MM-dd> - <initials> - <ticket number> - <what has changed>
```