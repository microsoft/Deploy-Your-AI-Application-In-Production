# Changelog

All notable changes to this project will be documented in this file.

## [1.3] - 2025-12-09
### Added
- Microsoft Fabric integration with automatic capacity creation and management
- Microsoft Purview integration for governance and data cataloging
- OneLake indexing pipeline connecting Fabric lakehouses to AI Search
- Comprehensive post-provision automation (22 hooks for Fabric/Purview/Search setup)
- New documentation: `deploy_app_from_foundry.md` for publishing apps from AI Foundry
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
