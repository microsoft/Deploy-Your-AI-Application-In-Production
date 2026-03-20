# Changelog

All notable changes to this project will be documented in this file.

## [2026-03-20]
### Added
- Read-only PostgreSQL mirroring preflight script for validating runner prerequisites before mirror setup
- PostgreSQL mirroring follow-up wrapper to run preflight, preparation, and mirror creation as a deliberate post-deployment flow
- Shared AI Search helper module for OneLake indexing scripts to centralize public network access toggles and tokenized REST calls

### Changed
- Repository documentation now uses Microsoft Foundry naming more consistently, including the README, deployment verification guide, and related runbooks
- PostgreSQL mirroring guidance now treats mirroring as a follow-up step after `azd up`, with clearer public-access versus private-network paths
- Postprovision now restores only PostgreSQL mirroring readiness preparation instead of attempting full mirror creation during the main deployment run
- PostgreSQL infrastructure outputs now expose the intended Fabric connection identity and default authentication settings needed for mirroring setup
- Fabric connection and workspace automation now resolve more values from deployment outputs, azd environment values, and deployed resources when transient hook context is incomplete
- PostgreSQL mirroring scripts now support explicit connection-mode outputs, stronger credential handling, clearer network-path failures, and gateway-aware Fabric connection creation
- Purview collection and Fabric datasource registration scripts now derive default names and deployment context more reliably from outputs and environment values
- Fabric workspace and capacity automation now tolerate more incomplete hook context, recover more reliably from existing resources, and improve capacity/workspace lookup behavior
- Preprovision retries the landing-zone deployment when Foundry account provisioning is still settling instead of failing immediately on transient provisioning-state errors
- Secure REST helpers now sanitize captured response bodies before surfacing API errors in automation logs
- Post-deployment and mirroring documentation consolidated the mirror workflow into a single primary runbook and clarified when mirroring should be deferred

### Removed
- Temporary PostgreSQL mirroring prep wrapper that toggled public access as a separate script
- Fabric connection probe debug script and the redundant PostgreSQL mirroring opt-in guide

## [2026-03-18]
### Added
- Parameter to override Log Analytics workspace resource ID and output mapping for automation scripts
- Optional `SKIP_PURVIEW_INTEGRATION` guard for Purview automation scripts (used by hooks when Purview is disabled)
- Retry/timeout handling for AI Search public network access toggles in OneLake indexing scripts

### Changed
- Preprovision error output simplified with concise failure reason and optional verbose diagnostics
- Main parameter file reordered into required/optional/defaulted sections with clearer comments
- OneLake indexing scripts prefer outputs, include AAD-only auth, and handle transient 409 run conflicts
- Post-deployment steps now include Fabric mirroring checklist items and Key Vault networking guidance for retrieving the `fabric_user` password

### Removed
- Log Analytics linkage script `scripts/automationScripts/FabricPurviewAutomation/connect_log_analytics.ps1`

## [1.3] - 2025-12-09
### Added
- Microsoft Fabric integration with automatic capacity creation and management
- Microsoft Purview integration for governance and data cataloging
- OneLake indexing pipeline connecting Fabric lakehouses to AI Search
- Comprehensive post-provision automation (22 hooks for Fabric/Purview/Search setup)
- New documentation: `deploy_app_from_foundry.md` for publishing apps from Microsoft Foundry
- New documentation: `TRANSPARENCY_FAQ.md` for responsible AI transparency
- New documentation: `NewUserGuide.md` for first-time users
- Header icons matching GSA standard format
- Fabric private networking documentation

### Changed
- README.md restructured to match Microsoft GSA (Global Solution Accelerator) format
- DeploymentGuide.md consolidated with all deployment options in one place
- Updated Azure Fabric CLI commands (`az fabric capacity` replaces deprecated `az powerbi embedded-capacity`)
- Post-provision scripts now validate Fabric capacity state before execution
- Navigation links use pipe separators matching other GSA repos

### Removed
- `github_actions_steps.md` (stub placeholder)
- `github_code_spaces_steps.md` (consolidated into DeploymentGuide.md)
- `local_environment_steps.md` (consolidated into DeploymentGuide.md)
- `Dev_ContainerSteps.md` (consolidated into DeploymentGuide.md)
- `transfer_project_connections.md` (feature deprecated)
- `sample_app_setup.md` (replaced with `deploy_app_from_foundry.md`)
- `Verify_Services_On_Network.md` (referenced non-existent script)
- `add_additional_services.md` (outdated, redundant with PARAMETER_GUIDE.md)
- `modify_deployed_models.md` (outdated, redundant with PARAMETER_GUIDE.md)

## [1.2] - 2025-05-13
### Added
- Add new project module leveraging the new cognitive services/projects type
- Add BYO service connections for search, storage and CosmosDB to project (based on feature flag selection)
- new infrastructure drawing

### Changed
- Revise Cognitive Services module to leverage new preview api to leverage new FDP updates
- Update AI Search CMK enforcement value to 'disabled'
- Update and add private endpoints for cognitive services project subtype
- Update and add required roles and scopes to cognitive services and ai search modules
- Update md to show changes

### Deprecated
- Remove the modules deploying AML hub and project.


## [1.1] - 2025-04-30
### Added
- Added feature to collect and connect existing connections from existing project when creating a new isolated 'production' project. 
- Added Change Log
- Added new md to explain the feature in depth.

### Changed
- Updates to the parameters to prompt user for true/false (feature flag) of connections

### Deprecated
- None



## [1.0] - 2025-03-10
### Added
- Initial release of the template.
