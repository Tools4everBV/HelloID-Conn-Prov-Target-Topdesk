
# HelloID-Conn-Prov-Target-Topdesk

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
    <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Topdesk/blob/main/Logo.png?raw=true">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-Topdesk](#helloid-conn-prov-target-topdesk)
	- [Table of contents](#table-of-contents)
	- [Introduction](#introduction)
	- [Getting started](#getting-started)
		- [Provisioning PowerShell V2 connector](#provisioning-powershell-v2-connector)
			- [Correlation configuration](#correlation-configuration)
			- [Field mapping](#field-mapping)
		- [Connection settings](#connection-settings)
		- [Prerequisites](#prerequisites)
		- [Remarks](#remarks)
	- [Setup the connector](#setup-the-connector)
		- [Remove attributes when updating a Topdesk person instead of correlating](#remove-attributes-when-updating-a-topdesk-person-instead-of-correlating)
		- [Disable department, budgetholder or manager](#disable-department-budgetholder-or-manager)
		- [Changes](#changes)
		- [Incidents](#incidents)
	- [Getting help](#getting-help)
	- [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-Topdesk_ is a _target_ connector. Topdesk provides a set of REST APIs that allow you to programmatically interact with its data. The [Topdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/) provides details of API commands that are used.

| Endpoint                           | Description                                                |
| ---------------------------------- | ---------------------------------------------------------- |
| /tas/api/persons                   | `GET / POST / PATCH` actions to read and write the persons |
| /tas/api/branches                  | `GET / POST` read and create branches                      |
| /tas/api/departments               | `GET / POST` read and create departments                   |
| /tas/api/budgetholders             | `GET / POST` read and create budgetholders                 |
| /tas/api/archiving-reasons         | `GET` archiving-reasons to archive persons                 |
| /tas/api/applicableChangeTemplates | `GET` read change template from Topdesk                    |
| /tas/api/operatorChanges           | `POST` create changes in Topdesk                           |
| /tas/api/incidents                 | `GET / POST` read and create incidents                     |
| /tas/api/operatorgroups            | `GET` read operator groups used for incidents              |
| /tas/api/operators                 | `GET` read operators used for incidents                    |
| /tas/api/countries                 | `GET` read countries used for create branches              |

The following lifecycle actions are available:

| Action                     | Description                                                                  |
| -------------------------- | ---------------------------------------------------------------------------- |
| create.ps1                 | PowerShell _create_ or _correlate_ lifecycle action                          |
| delete.ps1                 | PowerShell _delete_ lifecycle action (empty configured values and archive)   |
| disable.ps1                | PowerShell _disable_ lifecycle action                                        |
| enable.ps1                 | PowerShell _enable_ lifecycle action                                         |
| update.ps1                 | PowerShell _update_ lifecycle action                                         |
| grant.change.ps1           | PowerShell _grant_  lifecycle action (create change on entitlement grant)    |
| revoke.change.ps1          | PowerShell _revoke_ lifecycle action (create change on entitlement revoke)   |
| permissions.change.ps1     | PowerShell _permissions_ lifecycle action (read configured change.json)      |
| grant.incident.ps1         | PowerShell _grant_ lifecycle action (create incident on entitlement grant)   |
| revoke.incident.ps1        | PowerShell _revoke_ lifecycle action (create incident on entitlement revoke) |
| permissions.incident.ps1   | PowerShell _permissions_ lifecycle action (read configured incident.json)    |
| resources.branch.ps1       | PowerShell _resources_ lifecycle action (create braches)                     |
| resources.department.ps1   | PowerShell _resources_ lifecycle action (create departments)                 |
| resources.budgetholder.ps1 | PowerShell _resources_ lifecycle action (create budgetholders)               |
| configuration.json         | Default _configuration.json_                                                 |
| fieldMapping.json          | Default _fieldMapping.json_                                                  |

## Getting started

### Provisioning PowerShell V2 connector

#### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _HelloID-Conn-Prov-Target-Topdesk to a person in _HelloID_.

To properly setup the correlation:

1. Open the `Correlation` tab.

2. Specify the following configuration:

    | Setting                   | Value                             |
    | ------------------------- | --------------------------------- |
    | Enable correlation        | `True`                            |
    | Person correlation field  | `PersonContext.Person.ExternalId` |
    | Account correlation field | `employeeNumber`                  |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

#### Field mapping

The field mapping can be imported by using the [_fieldMapping.json_](./fieldMapping.json) file.

> [!IMPORTANT]
> If your current fieldmapping contains _[branch/department/budgetHolder].lookupValue_ you should replace this with _[].name_.

> [!TIP]
> You can add extra fields to the account mapping. For example `mobileNumber` or a boolean field `showAllBranches`. For all possible options please check the [Topdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/)

### Connection settings

The following settings are required to connect to the API.

| Setting                             | Description                                                                                                             | Mandatory |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | --------- |
| BaseUrl                             | The URL to the API                                                                                                      | Yes       |
| UserName                            | The UserName to connect to the API                                                                                      | Yes       |
| Password                            | The Password to connect to the API                                                                                      | Yes       |
| Notification file path              | Location of the JSON file needed for changes or incidents                                                               |           |
| Archiving reason                    | Fill in an archiving reason that is configured in Topdesk                                                               | Yes       |
| Fallback email                      | When a manager is set as the requester (in the JSON file) but the manager account reference is empty                    |           |
| Do not create changes or incidents  | If enabled no changes or incidents will be created in Topdesk                                                           |           |
| When no item is found in Topdesk    | Stop processing and generate an error or keep the current value and continue if budgetHolder or Department is not found | Yes       |
| When no department in source data   | Stop processing and generate an error or clear the department field in Topdesk                                          | Yes       |
| When no budgetholder in source data | Stop processing and generate an error or clear the budgetholder field in Topdesk                                        | Yes       |
| Toggle debug logging                | Creates extra logging for debug purposes                                                                                |

### Prerequisites
> [!IMPORTANT]
> <b> When changes or incidents are in scope, a helloID agent on-premise is required. For cloud only changes or incidents use the [HelloID Topdesk notification system](https://github.com/Tools4everBV/HelloID-Conn-Prov-Notification-Topdesk) </b> 

an archiving reason that is configured in Topdesk.
Credentials with the rights listed below. 

| Permission                       | Read | Write | Create | Archive |
| -------------------------------- | ---- | ----- | ------ | ------- |
| <b>Call Management</b>           |
| First line calls                 | x    | x     | x      |
| Second line calls                | x    | x     | x      |
| Escalate calls                   |      | x     |        |
| Link object to call              |      | x     |        |
| Link room to call                |      | x     |        |
| <b>Change Management</b>         |
| Requests for Simple Change       | x    | x     | x      |
| Requests for Extensive Change    | x    | x     | x      |
| Simple Changes                   | x    | x     |        |
| Extensive Changes                | x    | x     |        |
| <b>New Asset Management</b>      |
| Templates                        | x    |       |        |
| <b>Supporting Files</b>          |
| Persons                          | x    | x     | x      | x       |
| Operators                        | x    | x     | x      | x       |
| Operator groups                  | x    |       |        |
| Suppliers                        | x    |       |        |
| Rooms                            | x    |       |        |
| Login data                       |      | x     |        |
| Supporting Files Settings        | x    | x     |        |         |
| <b>Reporting API</b>             |
| REST API                         | x    |       |        |
| Use application passwords        |      | x     |        |
| <b>Asset Management - Assets</b> |
| Configuration                    | x    |       |        |         |
| Firsttemplate                    | x    |       |        |         |
| Hardware                         | x    |       |        |         |
| Inventories                      | x    |       |        |         |
| Licentie                         | x    |       |        |         |
| Network component                | x    |       |        |         |
| Software                         | x    |       |        |         |
| Stock                            | x    |       |        |         |
| Telephone systems                | x    |       |        |         |

> [!NOTE]
> It is possible to set filters in Topdesk. If you don't get a result from Topdesk when expecting one it is probably because filters are used. For example, searching for a branch that can't be found by the API user but is visible in Topdesk.


### Remarks

## Setup the connector

### Remove attributes when updating a Topdesk person instead of correlating
In the `update.ps1` script. There is an example of only set certain attributes when correlating a person, but skipping them when updating them.

```powershell
    if (-not($actionContext.AccountCorrelated -eq $true)) {
        # Example to only set certain attributes when create-correlate. If you don't want to update certain values, you need to remove them here.    
        # $account.PSObject.Properties.Remove('email')
        # $account.PSObject.Properties.Remove('networkLoginName')
        # $account.PSObject.Properties.Remove('tasLoginName')
    }
```

### Disable department, budgetholder or manager

The fields _department_, _budgetholder_ and _manager_ are non-required lookup fields in Topdesk. This means you first need to look up the field and then use the returned GUID (ID) to set the Topdesk person. 

For example:


```JSON
"id": "90ee5493-027d-4cda-8b41-8325130040c3",
"name": "EnYoi Holding B.V.",
"externalLinks": []
```

If you don't need the mapping of the fields in Topdesk, you can remove `department.name`, `budgetHolder.name` or `manager.id` from the field mapping. The create and update script will skip the lookup action. 

> [!IMPORTANT]
> The branch lookup value `branch.name` is still mandatory.

### Changes
It is possible to create changes in Topdesk when granting or revoking an entitlement in HelloID. The content of the changes is managed in a JSON file. The local HelloID agent needs to read this file.

Please map the correct account mapping in [_grantPermission.ps1_](./permissions/change/grantPermission.ps1) and [_revokePermission.ps1_](./permissions/change/revokePermission.ps1). If used in the JSON file.

```Powershell
# Map the account variables used in the JSON
$account = @{
    userPrincipalName = $personContext.Person.Accounts.MicrosoftActiveDirectory.userPrincipalName
    sAMAccountName    = $personContext.Person.Accounts.MicrosoftActiveDirectory.sAMAccountName
    mail              = $personContext.Person.Accounts.MicrosoftActiveDirectory.mail
	TopdeskAssets     = "'EnableGetAssets' not added in JSON or set to false" # Default message shown when using $account.TopdeskAssets
}
```

Please use the [_example.change.json_](./permissions/change/example.change.json) as a template to build you're own.

The change JSON file has the following structure:

```JSON
{
	"Identification": {
		"Id": "C001"
	},
	"DisplayName": "Aanvraag/Inname laptop",
	"Grant": {
		"Requester": "tester@test.com",
		"Request": "Graag een laptop gereed maken voor onderstaande medewerker.\n\nNaam: $($p.Name.NickName)\nAchternaam: $($p.Name.FamilyName)\nuserPrincipalName: $($account.userPrincipalName)\nsAMAccountName: $($account.sAMAccountName)\nPersoneelsnummer: $($p.ExternalId)\n\nFunctie: $($p.PrimaryContract.Title.Name)\nAfdeling: $($p.PrimaryContract.Department.DisplayName)",
		"Action": null,
		"BriefDescription": "Aanvraag Laptop ($($p.displayName))",
		"Template": "Ws 006",
		"Category": "Middelen",
		"SubCategory": "Inventaris & apparatuur",
		"ChangeType": "Simple",
		"Impact": "Persoon",
		"Benefit": null,
		"Priority": "P1",
		"EnableGetAssets": false,
		"SkipNoAssetsFound": false,
		"AssetsFilter": ""
	},
	"Revoke": {
		"Requester": "Employee",
		"Request": "Volgens onze informatie is onderstaande medewerker in het bezit van een laptop, deze dient op de laatste werkdag ingeleverd te worden bij zijn/haar direct leidinggevende.\n\nNaam: $($p.Name.NickName)\nAchternaam: $($p.Name.FamilyName)\nPersoneelsnummer: $($p.ExternalId)\n\nFunctie: $($p.PrimaryContract.Title.Name)\nAfdeling: $($p.PrimaryContract.Department.DisplayName)\n\nManager: $($p.PrimaryContract.Manager.DisplayName)\n\nAssets:\n$($account.TopdeskAssets)",
		"Action": null,
		"BriefDescription": "Inname Laptop ($($p.displayName))",
		"Template": "Ws 015",
		"Category": "Middelen",
		"SubCategory": "Inventaris & apparatuur",
		"ChangeType": "Simple",
		"Impact": "Persoon",
		"Benefit": null,
		"Priority": "P1",
		"EnableGetAssets": true,
		"SkipNoAssetsFound": true,
		"AssetsFilter": "Hardware,Software"
	}
}
```

| JSON field         | Description                                                                                                                                                                                                                                                                                                                                                                |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Id:                | Unique identifier in the JSON for HelloID. This cannot change!                                                                                                                                                                                                                                                                                                             |
| DisplayName:       | The value is shown when selecting the entitlement in HelloID.                                                                                                                                                                                                                                                                                                              |
| Grant / Revoke:    | It is possible to create a change when granting and revoking an entitlement. It is also possible to create a change when only granting or revoking an entitlement. Please look at the change_example.JSON to see how this works.                                                                                                                                           |
| Requester:         | It is possible to edit who is the requester of the change. You can fill in the E-mail of the Topdesk person or fill in `Employee` or `Manager`. Please note if the requester is an `Employee` or `Manager` the script will check if the person is archived. If the person is archived the script will activate the person, create the change and archive the person again. |
| Request:           | Fill in the request text. It is possible to use variables like $($p.Name.FamilyName) for the family name of the employee. Use \n for `enter`.                                                                                                                                                                                                                              |
| Action:            | Commonly filled in the Topdesk change template. If so use null.                                                                                                                                                                                                                                                                                                            |
| BriefDescription:  | Fill in the desired title of the change.                                                                                                                                                                                                                                                                                                                                   |
| Template:          | Fill in the Topdesk template code of the change. This is mandatory.                                                                                                                                                                                                                                                                                                        |
| Category:          | Commonly filled in the Topdesk change template. If so use null.                                                                                                                                                                                                                                                                                                            |
| SubCategory:       | Commonly filled in the Topdesk change template. If so use null.                                                                                                                                                                                                                                                                                                            |
| ChangeType:        | Fill in the change type `Simple` or `Extensive`.                                                                                                                                                                                                                                                                                                                           |
| Impact:            | Commonly filled in the Topdesk change template. If so use null.                                                                                                                                                                                                                                                                                                            |
| Benefit:           | Commonly filled in the Topdesk change template. If so use null.                                                                                                                                                                                                                                                                                                            |
| Priority:          | Commonly filled in the Topdesk change template. If so use null.                                                                                                                                                                                                                                                                                                            |
| EnableGetAssets:   | Set this value `true` for querying the assets that are linked to the person.                                                                                                                                                                                                                                                                                               |
| SkipNoAssetsFound: | Set this value `true` if no change must be created when no asset is found.                                                                                                                                                                                                                                                                                                 |
| AssetsFilter:      | For the type of assets that need to be queried. Use `,` between the types when querying more than one. Beware that the values are case-sensitive. Leave empty to query all assets.                                                                                                                                                                                         |

### Incidents
It is possible to create incidents in Topdesk when granting or revoking an entitlement in HelloID. The content of the incidents is managed in a JSON file. The local HelloID agent needs to read this file.

Please map the correct account mapping in [_grantPermission.ps1_](./permissions/incident/grantPermission.ps1) and [_revokePermission.ps1_](./permissions/incident/revokePermission.ps1). If used in the JSON file.

```Powershell
# Map the account variables used in the JSON
$account = @{
    userPrincipalName = $personContext.Person.Accounts.MicrosoftActiveDirectory.userPrincipalName
    sAMAccountName    = $personContext.Person.Accounts.MicrosoftActiveDirectory.sAMAccountName
    mail              = $personContext.Person.Accounts.MicrosoftActiveDirectory.mail
	TopdeskAssets     = "'EnableGetAssets' not added in JSON or set to false" # Default message shown when using $account.TopdeskAssets
}
```

Please use the [_example.incident.json_](./permissions/incident/example.incident.json) as a template to build you're own.

> [!TIP]
> If you want to look up for example operator with 'employeeNumber'. Then you should change the SearchAttribute field like in the example below. Make sure you name the SearchAttribute the same as Topdesk uses. You can verifier this in the [Topdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/Operators/retrieveOperators)

```powershell
     # Resolve operator id 
    if (-not [string]::IsNullOrEmpty($template.Operator)) {
        $splatParamsOperator = @{
            BaseUrl         = $actionContext.Configuration.baseUrl
            Headers         = $authHeaders
            Class           = 'Operator'
            Value           = $template.Operator
            Endpoint        = '/tas/api/operators'
            SearchAttribute = 'email'
        }
    
        #Add Impact to request object
        $requestObject += @{
            operator = @{
                id = Get-TopdeskIdentifier @splatParamsOperator
            }
        }
    }
```

The incident JSON file has the following structure:

```JSON
{
	"Identification": {
		"Id": "I001"
	},
	"DisplayName": "Aanvraag/Inname laptop",
	"Grant": {
		"Caller": "tester@test.com",
		"RequestShort": "Aanvraag Laptop ($($p.displayName))",
		"RequestDescription": "<b>Graag een laptop gereed maken voor onderstaande medewerker.</b><br><br><em>Naam: $($p.Name.NickName)</em><br><strong>Achternaam: $($p.Name.FamilyName)</strong><br>userPrincipalName: $($account.userPrincipalName)<br>sAMAccountName: $($account.sAMAccountName)<br><u>Personeelsnummer: $($p.ExternalId)</u><br><br>Functie: $($p.PrimaryContract.Title.Name)<br><i>Afdeling: $($p.PrimaryContract.Department.DisplayName)</i><br><br><a href='https://www.tools4ever.nl/'>Visit Tools4ever.nl!</a>",
		"Action": "<b>Medewerker ($($p.displayName)) heeft een laptop nodig</b><br><br>Graag gereed maken voor $($p.PrimaryContract.StartDate).",
		"Branch": "Baarn",
		"OperatorGroup": "Applicatiebeheerders",
		"Operator": null,
		"Category": "Middelen",
		"SubCategory": "Inventaris & apparatuur",
		"CallType": "Aanvraag",
		"Impact": null,
		"Priority": null,
		"Duration": null,
		"EntryType": null,
		"Urgency": null,
		"ProcessingStatus": null,
		"EnableGetAssets": false,
		"SkipNoAssetsFound": false,
		"AssetsFilter": ""
	},
	"Revoke": {
		"Caller": "tester@test.com",
		"RequestShort": "Inname Laptop ($($p.displayName))",
		"RequestDescription": "Volgens onze informatie is onderstaande medewerker in het bezit van een laptop, deze dient op de laatste werkdag ingeleverd te worden bij zijn/haar direct leidinggevende.<br><br>Naam: $($p.Name.NickName)<br>Achternaam: $($p.Name.FamilyName)<br>Personeelsnummer: $($p.ExternalId)<br><br>Functie: $($p.PrimaryContract.Title.Name)<br>Afdeling: $($p.PrimaryContract.Department.DisplayName)<br><br>Manager: $($p.PrimaryContract.Manager.DisplayName)<br><br>Assets:<br>$($account.TopdeskAssets)",
		"Action": "<b>Medewerker ($($p.displayName)) is in het bezit van een laptop</b>.",
		"Branch": "Baarn",
		"OperatorGroup": "Applicatiebeheerders",
		"Operator": null,
		"Category": "Middelen",
		"SubCategory": "Inventaris & apparatuur",
		"CallType": "Aanvraag",
		"Impact": null,
		"Priority": null,
		"Duration": null,
		"EntryType": null,
		"Urgency": null,
		"ProcessingStatus": null,
		"EnableGetAssets": true,
		"SkipNoAssetsFound": true,
		"AssetsFilter": "Hardware,Software"
	}
}
```
| JSON field          | Description                                                                                                                                                                                                                                                                                                                                                             |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Id:                 | Unique identifier in the JSON for HelloID.                                                                                                                                                                                                                                                                                                                              |
| DisplayName:        | The value is shown when selecting the entitlement in HelloID.                                                                                                                                                                                                                                                                                                           |
| Grant / Revoke:     | It is possible to create an incident when granting and revoking an entitlement. It is also possible to create an incident when only granting or revoking an entitlement. Please look at the incident_example.json to see how this works.                                                                                                                                |
| Caller:             | It is possible to edit who is the caller of the change. You can fill in the E-mail of the Topdesk person or fill in 'Employee' or 'Manager'. Please note if the requester is an 'Employee' or 'Manager' the script will check if the person is archived. If the person is archived the script will activate the person, create the change and archive the person again. |
| RequestShort:       | Fill in the desired title of the incident. Size range: maximum 80 characters. It is possible to use variables like $($p.Name.FamilyName) for the family name of the employee.                                                                                                                                                                                           |
| RequestDescription: | Fill in the request text. It is possible to use variables like $($p.Name.FamilyName) for the family name of the employee. Use <'br'> to enter. For more HTML tags: [Topdesk incident API documentation](https://developers.topdesk.com/documentation/index-apidoc.html#api-Incident-CreateIncident)                                                                     |
| Action:             | Fill in the action field if needed. If not used fill in null. It is possible to use variables like $($p.Name.FamilyName) for the family name of the employee. Use <'br'> to enter. For more HTML tags: [Topdesk incident API documentation](https://developers.topdesk.com/documentation/index-apidoc.html#api-Incident-CreateIncident)                                 |
| Branch:             | Fill in the branch name that is used in Topdesk. This is a mandatory lookup field.                                                                                                                                                                                                                                                                                      |
| OperatorGroup:      | Fill in the operator group name that is used in Topdesk. It is possible to disable this lookup field by using the value null. If marked mandatory in Topdesk this will be shown when opening the incident.                                                                                                                                                              |
| Operator:           | Fill in the operator email that is used in Topdesk. It is possible to disable this lookup field by using the value null. If marked mandatory in Topdesk this will be shown when opening the incident.                                                                                                                                                                   |
| Category:           | Fill in the category name that is used in Topdesk. It is possible to disable this lookup field by using the value null. If marked mandatory in Topdesk this will be shown when opening the incident.                                                                                                                                                                    |
| SubCategory:        | Fill in the subcategory name that is used in Topdesk. It is possible to disable this lookup field by using the value null. If marked mandatory in Topdesk this will be shown when opening the incident.                                                                                                                                                                 |
| CallType:           | Fill in the branch call type that is used in Topdesk. It is possible to disable this lookup field by using the value null. If marked mandatory in Topdesk this will be shown when opening the incident.                                                                                                                                                                 |
| Impact:             | Fill in the impact name that is used in Topdesk. It is possible to disable this lookup field by using the value null. If marked mandatory in Topdesk this will be shown when opening the incident.                                                                                                                                                                      |
| Priority:           | Fill in the priority name that is used in Topdesk. It is possible to disable this lookup field by using the value null. If marked mandatory in Topdesk this will be shown when opening the incident.                                                                                                                                                                    |
| Duration:           | Fill in the duration name that is used in Topdesk. It is possible to disable this lookup field by using the value null. If marked mandatory in Topdesk this will be shown when opening the incident.                                                                                                                                                                    |
| EntryType:          | Fill in the entry type name that is used in Topdesk. It is possible to disable this lookup field by using the value null. If marked mandatory in Topdesk this will be shown when opening the incident.                                                                                                                                                                  |
| Urgency:            | Fill in the urgency name that is used in Topdesk. It is possible to disable this lookup field by using the value null. If marked mandatory in Topdesk this will be shown when opening the incident.                                                                                                                                                                     |
| ProcessingStatus:   | Fill in the processing status name that is used in Topdesk. It is possible to disable this lookup field by using the value null. If marked mandatory in Topdesk this will be shown when opening the incident. With the correct processing status, it is possible to create a closed incident.                                                                           |
| EnableGetAssets:    | Set this value `true` for querying the assets that are linked to the person.                                                                                                                                                                                                                                                                                            |
| SkipNoAssetsFound:  | Set this value `true` if no incident must be created when no asset is found.                                                                                                                                                                                                                                                                                            |
| AssetsFilter:       | For the type of assets that need to be queried. Use `,` between the types when querying more than one. Beware that the values are case-sensitive. Leave empty to query all assets.                                                                                                                                                                                      |

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com/forum/helloid-connectors/provisioning/1266-helloid-conn-prov-target-topdesk)._

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/

