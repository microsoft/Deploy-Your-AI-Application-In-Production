# Changelog

All notable changes to this project will be documented in this file.

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
