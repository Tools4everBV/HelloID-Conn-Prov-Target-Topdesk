# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [3.5.0] - 02-03-2026

List of changes:
- Added `SkipAssetsFound` option for change and incident notifications to skip creating a Topdesk change/incident when one or multiple assets are found
- Updated change and incident grant/revoke scripts to support the new skip flow and improved action-skip audit logging
- Updated example permission JSON files for change and incident with `SkipAssetsFound` configuration
- Updated documentation (`README.md`) with the new asset-skip behavior and refreshed connector setup/reference sections

## [3.4.3] - 06-02-2026

List of changes:
- Removed `lookupErrorTopdesk` [#44](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Topdesk/issues/44)
- `Confirm-Description` now shorten the `BriefDescription` and `requestShort`
- Added support to not update branch in update script (when not update is not selected on `branch.name`)
- Fixed [#37](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Topdesk/issues/37)

## [3.4.2] - 19-01-2026

Updated contract endpoint datetime conversion for better timezone support.
Added better logging when isManager flag is changed.

## [3.4.1] - 19-01-2026

Added MainframeLoginName field mapping with fixed values for managed/deleted states

## [3.4.0] - 27-05-2025

Added support for specifying the status field (firstLine or secondLine) on incidents

## [3.4.0] - 14-03-2025

List of changes:
- Added account import script
- Enhanced error handling resource scripts ([#32](https://github.com/Tools4everBV/HelloID-Conn-Prov-Target-Topdesk/issues/32))
- Optimized audit logging

## [3.3.0] - 10-12-2024

Added examples for adding additional endpoints and removed debug toggle

## [3.2.0] - 25-11-2024

Added query assets support

## [3.1.1] - 28-08-2024

Small fixes

## [3.1.0] - 11-07-2024

Added fieldmapping and rework readme

## [3.0.0] - 14-01-2024

This is the first release of powershell v2

## [2.0.3] - 22-12-2023

Latest release of powershell v1

### Added

### Changed

### Deprecated

### Removed