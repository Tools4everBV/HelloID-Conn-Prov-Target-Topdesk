# HelloID-Conn-Prov-Target-TOPdesk

| :warning: Warning |
|:---------------------------|
| Note that this connector is **not ready** to use in your production environment.       |

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.       |

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
  + [Remarks](#Remarks)
- [Setup the connector](@Setup-The-Connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-TOPdesk_ is a _target_ connector. TOPdesk provides a set of REST API's that allow you to programmatically interact with it's data. The HelloID connector uses the API endpoints listed in the table below.

| Endpoint     | Description |
| ------------ | ----------- |
|              |             |

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting                             | Description                                                                       | Mandatory   |
| ------------                        | -----------                                                                       | ----------- |
| BaseUrl                             | The URL to the API                                                                | Yes         |
| UserName                            | The UserName to connect to the API                                                | Yes         |
| Password                            | The Password to connect to the API                                                | Yes         |
| Notification file path              | Location of the chance or incident .json                                          | No          |
| Archiving reason                    | Fill in a archiving reason that is configured in TOPdesk                          | Yes         |
| Fallback email                      | When a manager is set as the requester but the manager account reference is empty | No          |
| Toggle debug logging                | Creates extra logging for debug purposes                                          |             |
| Do not create changes or incidents  | If enabled no changes or incidents will be created in topdesk                     |             |
| When no item found in TOPdesk       | Stop prcessing and generate an error or keep the current value and continue       |             |
| When no deparment in source data    | Stop prcessing and generate an error or clear deparment field in TOPdesk          |             |
| When no budgetholder in source data | Stop prcessing and generate an error or clear budgetholder field in TOPdesk       |             |
| When manager reference is empty     | Stop prcessing and generate an error or clear manager field in TOPdesk            |             |

### Prerequisites
  - When creating changes or incidents a helloID agent on-prem is required
  - Archiving reason that is configured in TOPdesk
  - Credentials with the rights as descripted in permissions

### Permissions

The following permissions are required to use this connector. This should be configured on a specific Permission Group for the Operator HelloID uses.
<table>
<tr><td>Permission</td><td>Read</td><td>Write</td><td>Create</td><td>Archive</td></tr>

<tr><td><b>Call Management</b></td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>First line calls</td><td>x</td><td>x</td><td>x</td><td>&nbsp;</td></tr>
<tr><td>Second line calls</td><td>x</td><td>x</td><td>x</td><td>&nbsp;</td></tr>
<tr><td>Escalate calls</td><td>&nbsp;</td><td>x</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>Link object to call</td><td>&nbsp;</td><td>x</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>Link room to call</td><td>&nbsp;</td><td>x</td><td>&nbsp;</td><td>&nbsp;</td></tr>

<tr><td><b>Change Management</b></td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>Requests for Simple Change</td><td>x</td><td>x</td><td>x</td><td>&nbsp;</td></tr>
<tr><td>Requests for Extensive Change</td><td>x</td><td>x</td><td>x</td><td>&nbsp;</td></tr>
<tr><td>Simple Changes</td><td>x</td><td>x</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>Extensive Changes</td><td>x</td><td>x</td><td>&nbsp;</td><td>&nbsp;</td></tr>

<tr><td><b>New Asset Management</b></td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>Templates</td><td>x</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>

<tr><td><b>Supporting Files</b></td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>Persons</td><td>x</td><td>x</td><td>x</td><td>x</td></tr>
<tr><td>Operators</td><td>x</td><td>x</td><td>x</td><td>x</td></tr>
<tr><td>Operator groups</td><td>x</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>Suppliers</td><td>x</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>Rooms</td><td>x</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>Login data</td><td>&nbsp;</td><td>x</td><td>&nbsp;</td><td>&nbsp;</td></tr>

<tr><td><b>Reporting API</b></td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>REST API</td><td>x</td><td>&nbsp;</td><td>&nbsp;</td><td>&nbsp;</td></tr>
<tr><td>Use application passwords</td><td>&nbsp;</td><td>x</td><td>&nbsp;</td><td>&nbsp;</td></tr>

</table>

(To create departments and budgetholders, you will need to allow the API account read and write access to the "Instellingen voor Ondersteunende bestanden".)

### Remarks

## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Only require tickets
Instruction to only require tickets. (Requester is always fixed)
Re-implementation required if persons need to be managed later
(must edit this part)


## Extra fields
To add the extra fields, you can insert the following code here.... and there... etc(must edit this part)

## Error messages
Branch
> Requested to lookup branch, but branch.lookupValue is missing. This is a scripting issue.
> The lookup value for Branch is empty but it's a required field.
> Branch with name [<name>] isn't found in Topdesk but it's a required field.
Department
> Requested to lookup department, but department.lookupValue is not set. This is a scripting issue.
> The lookup value for Department is empty and the connector is configured to stop when this happens.
> Department [<name>] not found in Topdesk and the connector is configured to stop when this happens.
Budgetholder
> Requested to lookup Budgetholder, but budgetholder.lookupValue is missing. This is a scripting issue.
> The lookup value for Budgetholder is empty and the connector is configured to stop when this happens.
> Budgetholder [<name>] not found in Topdesk and the connector is configured to stop when this happens.



## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
