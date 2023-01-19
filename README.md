# HelloID-Conn-Prov-Target-TOPdesk

| :warning: Warning |
|:-|
| Note that this connector is **not ready** to use in your production environment. |

| :information_source: Information |
|:-|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |

<p align="center">
  <img src="assets/logo.png">
</p>

## Versioning
| Version | Description | Date |
| - | - | - |
| 2.0.0   | Release of v2 connector including performance and logging upgrades | fill in date  |
| 1.0.0   | Initial release | 2020/06/24  |

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Permissions](#Permissions)
- [Setup the connector](#Setup-The-Connector)
  + [Disable department or budgetholder](#Disable-department-or-budgetholder)
  + [Extra fields](#Extra-fields)
  + [Changes](#Changes)
  + [Incidents](#Incidents)
- [Remarks](#Remarks)
  + [Only require tickets](#Only-require-tickets)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-TOPdesk_ is a _target_ connector. TOPdesk provides a set of REST API's that allow you to programmatically interact with it's data. The [TOPdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/) provides details of API commando's that are used.

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting |Description | Mandatory 
| - | - | - 
| BaseUrl | The URL to the API | Yes 
| UserName| The UserName to connect to the API | Yes 
| Password | The Password to connect to the API | Yes 
| Notification file path | Location of the JSON file needed for changes or incidents | No 
| Archiving reason | Fill in a archiving reason that is configured in TOPdesk | Yes 
| Fallback email | When a manager is set as the requester (in the JSON file) but the manager account reference is empty | No 
| Toggle debug logging | Creates extra logging for debug purposes |
| Do not create changes or incidents | If enabled no changes or incidents will be created in topdesk |
| When no item found in TOPdesk | Stop prcessing and generate an error or keep the current value and continue |
| When no deparment in source data | Stop prcessing and generate an error or clear deparment field in TOPdesk |
| When no budgetholder in source data | Stop prcessing and generate an error or clear budgetholder field in TOPdesk | 
| When manager reference is empty | Stop prcessing and generate an error or clear manager field in TOPdesk |

### Prerequisites
  - When creating changes or incidents a helloID agent on-prem is required
  - Archiving reason that is configured in TOPdesk
  - Credentials with the rights as descripted in permissions

### Permissions

The following permissions are required to use this connector. This should be configured on a specific Permission Group for the Operator HelloID uses.

| Permission | Read | Write | Create | Archive
| - | - | - | - | -
| <b>Call Management</b>
| First line calls | x | x | x | 
| Second line calls | x | x | x |
| Escalate calls | | x | |
| Link object to call | | x | |
| Link room to call | | x | |
| <b>Change Management</b>
| Requests for Simple Change | x | x | x | 
| Requests for Extensive Change | x | x | x |
| Simple Changes| x | x | |
| Extensive Changes | x | x | |
| <b>New Asset Management</b>
| Templates | x |  | |
| <b>Supporting Files</b>
| Persons | x | x | x | x
| Operators | x | x | x | x
| Operator groups | x |  |  | 
| Suppliers | x |  |  | 
| Rooms | x |  |  | 
| Login data |  | x |  | 
| <b>Reporting API</b>
| REST API | x |  |  | 
| Use application passwords |  | x |  | 

(To create departments and budgetholders, you will need to allow the API account read and write access to the "Instellingen voor Ondersteunende bestanden".)

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

### Disable department or budgetholder

The fields department and budgetholder are both non required lookup fields in topdesk. This means you first need to lookup the field and then use the returned GUID (ID) to set the topdesk person. 

For example:


```JSON
"id": "90ee5493-027d-4cda-8b41-8325130040c3",
"name": "EnYoi Holding B.V.",
"externalLinks": []
```

If you don't need the mapping of deparment or budgetholder in Topdesk. It is nesceary to comment out both mapping and the call function in the script.

Example for department:

Mapping:

```powershell
# department          = @{ lookupValue = $p.PrimaryContract.Department.DisplayName }
```

Call function:

```powershell
# Resolve department id
# $splatParamsDepartment = @{
#     Account                   = [ref]$account
#     AuditLogs                 = [ref]$auditLogs
#     Headers                   = $authHeaders
#     BaseUrl                   = $config.baseUrl
#     LookupErrorHrDepartment   = $config.lookupErrorHrDepartment
#     LookupErrorTopdesk        = $config.lookupErrorTopdesk
# }
# Get-TopdeskDepartment @splatParamsDepartment
```

### Extra fields
You can add extra fields by adding them to the account mapping. For all possbile options please check the [TOPdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/).

Example for mobileNumber:

```powershell
# Account mapping. See for all possible options the Topdesk 'supporting files' API documentation at
# https://developers.topdesk.com/explorer/?page=supporting-files#/Persons/createPerson
$account = [PSCustomObject]@{
    # other mapping fields are here
    mobileNumber        = $p.Contact.Business.Phone.Mobile
}
```

### Changes
It is possible to create changes in TOPdesk when granting or revoking an entitlement in HelloID. The content of the changes is managed in a JSON file. The local HelloID agent needs to read this file.

Please use the exampleChanges.json as a template to build you're own.

The change JSON file has the following structure:

```JSON
{
		"Identification": {
			"Id": "C001"
		},
		"DisplayName": "Aanvraag/Inname laptop",
		"Grant": {
			"Requester": "tester@test.com",
			"Request": "Graag een laptop gereed maken voor onderstaande medewerker.\n\nNaam: $($p.Name.NickName)\nAchternaam: $($p.Name.FamilyName)\nPersoneelsnummer: $($p.ExternalId)\n\nFunctie: $($p.PrimaryContract.Title.Name)\nAfdeling: $($p.PrimaryContract.Department.DisplayName)",
			"Action": null,
			"BriefDescription": "Aanvraag Laptop ($($p.displayName))",
			"Template": "Ws 006",
			"Category": "Middelen",
			"SubCategory": "Inventaris & apparatuur",
			"ChangeType": "Simple",
			"Impact": "Persoon",
			"Benefit": null,
			"Priority": "P1"
		},
		"Revoke": {
			"Requester": "Employee",
			"Request": "Volgens onze informatie is onderstaande medewerker in het bezit van een laptop, deze dient op de laatste werkdag ingeleverd te worden bij zijn/haar direct leidinggevende.\n\nNaam: $($p.Name.NickName)\nAchternaam: $($p.Name.FamilyName)\nPersoneelsnummer: $($p.ExternalId)\n\nFunctie: $($p.PrimaryContract.Title.Name)\nAfdeling: $($p.PrimaryContract.Department.DisplayName)\n\nManager: $($p.PrimaryContract.Manager.DisplayName)",
			"Action": null,
			"BriefDescription": "Inname Laptop ($($p.displayName))",
			"Template": "Ws 015",
			"Category": "Middelen",
			"SubCategory": "Inventaris & apparatuur",
			"ChangeType": "Simple",
			"Impact": "Persoon",
			"Benefit": null,
			"Priority": "P1"
		}
	}
```

| JSON field | Description
| - | -
| Id: | Unique identifier in the JSON for HelloID.
| DisplayName: | The value is shown when selecting the entitlement in HelloID.
| Grant / Revoke: | It is possible to create a change when granting and revoking an entitlement. It is also possible to create a change when only granting or revoking an entitlement. Please look at the exampleChanges.JSON to see how this works.
| Requester: | It is possible to edit who is the requester of the change. You can fill in the E-mail of the topdesk person or fill in 'Employee' or 'Manager'. Use \n for "enter". Please note if the requester is an 'Employee' or 'Manager' the script will check if the person is archived. If the person is archived the script will activate the person, create the change and archive the person again.
| Request: | Fill in the request text. It is possible to use variables like $($p.Name.FamilyName) for the family name of the employee. 
| Action: | Commenly filled in the TOPdesk change template. If so use null.
| BriefDescription: | Fill in the desired title of the change.
| Template: | Fill in the TOPdesk template code of the change. This is mandatory.
| Category: | Commenly filled in the TOPdesk change template. If so use null.
| SubCategory: | Commenly filled in the TOPdesk change template. If so use null.
| ChanageType: | Fill in the change type Simple or Extensive.
| Impact: | Commenly filled in the TOPdesk change template. If so use null.
| Benefit: | Commenly filled in the TOPdesk change template. If so use null.
| Priority: | Commenly filled in the TOPdesk change template. If so use null.

### Incidents
It is possible to create incidents in TOPdesk when granting or revoking an entitlement in HelloID. The content of the incidents is managed in a JSON file. The local HelloID agent needs to read this file.

Please use the exampleIncidents.json as a template to build you're own.

| :information_source: Information |
|:-|
| If you want to look up for example operator with 'employeeNumber'. Then you should change the SearchAttribute field like in the example below. Make sure you name the SearchAttribute the same as Topdesk uses. You can verifier this in the [TOPdesk API documentation](https://developers.topdesk.com/explorer/?page=supporting-files#/Operators/retrieveOperators) |
```powershell
     # Resolve operator id 
    $splatParamsOperator = @{
        AuditLogs       = [ref]$auditLogs
        BaseUrl         = $config.baseUrl
        Headers         = $authHeaders
        Class           = 'Operator'
        Value           = $template.Operator
        Endpoint        = '/tas/api/operators'
        SearchAttribute = 'employeeNumber' #SearchAttribute chaged from 'email' -> 'employeeNumber'
    }
    
     #Add Impact to request object
    $requestObject += @{
        operator = @{
            id = Get-TopdeskIdentifier @splatParamsOperator
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
			"RequestDescription": "Graag een laptop gereed maken voor onderstaande medewerker.\n\nNaam: $($p.Name.NickName)\nAchternaam: $($p.Name.FamilyName)\nPersoneelsnummer: $($p.ExternalId)\n\nFunctie: $($p.PrimaryContract.Title.Name)\nAfdeling: $($p.PrimaryContract.Department.DisplayName)",
			"Branch": "Baarn",
			"OperatorGroup": "Applicatiebeheerders",
			"Operator": null,
			"Category": "Middelen",
			"SubCategory": "Inventaris & apparatuur",
			"CallType": "Aanvraag",
			"Impact": null,
			"Priority": null,
			"EntryType": null,
			"Urgency": null,
			"ProcessingStatus": null
		},
		"Revoke": {
			"Caller": "tester@test.com",
			"RequestShort": "Inname Laptop ($($p.displayName))",
			"RequestDescription": "Volgens onze informatie is onderstaande medewerker in het bezit van een laptop, deze dient op de laatste werkdag ingeleverd te worden bij zijn/haar direct leidinggevende.\n\nNaam: $($p.Name.NickName)\nAchternaam: $($p.Name.FamilyName)\nPersoneelsnummer: $($p.ExternalId)\n\nFunctie: $($p.PrimaryContract.Title.Name)\nAfdeling: $($p.PrimaryContract.Department.DisplayName)\n\nManager: $($p.PrimaryContract.Manager.DisplayName)",
			"Branch": "Baarn",
			"OperatorGroup": "Applicatiebeheerders",
			"Operator": null,
			"Category": "Middelen",
			"SubCategory": "Inventaris & apparatuur",
			"CallType": "Aanvraag",
			"Impact": null,
			"Priority": null,
			"EntryType": null,
			"Urgency": null,
			"ProcessingStatus": null
		}
	}
```
| JSON field | Description
| - | -
| Id: | Unique identifier in the JSON for HelloID.
| DisplayName: | The value is shown when selecting the entitlement in HelloID.
| Grant / Revoke: | It is possible to create an incident when granting and revoking an entitlement. It is also possible to create an incident when only granting or revoking an entitlement. Please look at the exampleIncident.JSON to see how this works.
| Caller: | It is possible to edit who is the caller of the change. You can fill in the E-mail of the topdesk person or fill in 'Employee' or 'Manager'. Use \n for "enter". Please note if the requester is an 'Employee' or 'Manager' the script will check if the person is archived. If the person is archived the script will activate the person, create the change and archive the person again.
| RequestShort: | Fill in the desired title of the incident.
| RequestDescription: | Fill in the request text. It is possible to use variables like $($p.Name.FamilyName) for the family name of the employee.
| Branch: | Fill in the branch name that is used in Topdesk. This is a mandatory lookup field.
| OperatorGroup: | Fill in the operator group name that is used in Topdesk. It is possible to disable this lookup field by using the vallue null. If marked mandatory in Topdesk this will be shown when opening the incident.
| Operator: | Fill in the operator email that is used in Topdesk. It is possible to disable this lookup field by using the vallue null. If marked mandatory in Topdesk this will be shown when opening the incident.
| Category: | Fill in the category name that is used in Topdesk. It is possible to disable this lookup field by using the vallue null. If marked mandatory in Topdesk this will be shown when opening the incident.
| SubCategory: | Fill in the subcategory name that is used in Topdesk. It is possible to disable this lookup field by using the vallue null. If marked mandatory in Topdesk this will be shown when opening the incident.
| CallType: | Fill in the branch call type that is used in Topdesk. It is possible to disable this lookup field by using the vallue null. If marked mandatory in Topdesk this will be shown when opening the incident.
| Impact: | Fill in the impact name that is used in Topdesk. It is possible to disable this lookup field by using the vallue null. If marked mandatory in Topdesk this will be shown when opening the incident.
| Priority: | Fill in the priority name that is used in Topdesk. It is possible to disable this lookup field by using the vallue null. If marked mandatory in Topdesk this will be shown when opening the incident.
| EntryType: | Fill in the entry type name that is used in Topdesk. It is possible to disable this lookup field by using the vallue null. If marked mandatory in Topdesk this will be shown when opening the incident.
| Urgency: | Fill in the urgency name that is used in Topdesk. It is possible to disable this lookup field by using the vallue null. If marked mandatory in Topdesk this will be shown when opening the incident.
| ProcessingStatus: | Fill in the processing status name that is used in Topdesk. It is possible to disable this lookup field by using the vallue null. If marked mandatory in Topdesk this will be shown when opening the incident. With the correct processing status, it is possible to create a closed incident.

## Remarks

### Only require tickets
When persons are created with the TOPdesk AD sync for example. Then it should be possible to create incidents or changes. There is a correlation needed including a manager's reference to make this work properly. 
> TODO: make a separate create script to create the references (like AD/Azure prem.)

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

> The official HelloID documentation can be found at: https://docs.helloid.com/
