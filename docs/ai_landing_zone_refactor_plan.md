# AI Landing Zone Integration Plan

## Objective
Refactor this repository so that it consumes the Azure AI Landing Zone Bicep implementation as a Git submodule. Parameters, configuration, and deployment orchestration remain defined in this repo, while template specs for the AI Landing Zone modules are built and published from the submodule source. Keep the current sample application deployment experience intact and layer the AI Landing Zone capabilities on top.

## Current State Snapshot
- `infra/main.bicep` orchestrates application infrastructure: AI Foundry (Azure OpenAI), Cognitive Services, Azure AI Search, Cosmos DB, optional APIM, ACR, storage, Key Vault, VNet/Bastion jump box, Log Analytics, App Insights, and AI Foundry project wiring.
- Deployment tooling: `azure.yaml` (AZD), infra modules under `infra/modules`, scripts for provisioning and sample data seeding, GitHub Actions guidance in `docs/`.
- No existing submodules or template spec packaging; infra is deployed directly from local Bicep files.

## Target State Overview
- Add `infra/ai-landing-zone` as a Git submodule pointing to `https://github.com/Azure/AI-Landing-Zones.git` (rooted at `bicep/`).
- Introduce orchestration Bicep in this repo that maps existing parameters to AI Landing Zone module inputs (management groups, policy assignments, logging, networking, identity, etc.).
- Publish Template Specs for AI Landing Zone modules via automated pipeline (GitHub Actions/AZD pipeline) sourced from the submodule and referenced by resource ID in deployments from this repo.
- Preserve sample app deployment (app service, data services) while ensuring dependencies on AI Landing Zone resources (network, policy) are honored.

## Proposed Repository Layout (post-refactor)
```
infra/
  main.bicep
  landing-zone.orchestrator.bicep
  template-specs/
    publish-template-specs.yml
modules/
  ... (existing app modules retained)
submodules/
  ai-landing-zone/  (Git submodule -> Azure/AI-Landing-Zones/bicep)
scripts/
  publish_template_specs.sh
  deploy_landing_zone.sh
```

## Work Breakdown & Effort Estimate
| Phase | Duration (ideal days) | Key Outcomes |
| ----- | --------------------- | ------------ |
| 0. Discovery & Alignment | 3 | Confirm landing zone scope, management group strategy, required Azure permissions, template spec naming, environments. |
| 1. Repo Restructure | 4 | Add submodule, scaffold new orchestration Bicep, document parameter mapping, update AZD manifest. |
| 2. Template Spec Pipeline | 5 | Author reusable template spec definitions, create publish scripts/pipelines, validate deployment of specs to shared RG. |
| 3. Integration & Validation | 6 | Update `main.bicep` to consume template specs, ensure sample app resources align with policies/VNet from landing zone, run end-to-end deployment in sandbox. |
| 4. Hardening & Documentation | 3 | Update docs, add rollback guidance, capture runbooks, ensure CI templates handle submodule checkout. |
| **Total** | **21 ideal days (~4.5 weeks with buffers)** | Includes testing, reviews, and cross-team approvals. |

Assumptions: 1-2 engineers familiar with Azure Bicep and landing zone patterns, access to management group-level permissions, and availability of at least two Azure subscriptions for validation.

## Detailed Steps
### Phase 0 – Discovery
1. Inventory current deployed resources and identify overlaps with AI Landing Zone modules (network, policy, logging).
2. Decide management group hierarchy & subscriptions that AI Landing Zone will manage.
3. Align on template spec hosting resource group, naming standards, and RBAC model.
4. Capture parameter deltas between `infra/main.bicep` and AI Landing Zone modules.

### Phase 1 – Repo Restructure
1. Create submodule: `git submodule add https://github.com/Azure/AI-Landing-Zones.git submodules/ai-landing-zone`.
2. Add `infra/landing-zone.orchestrator.bicep` to encapsulate AI Landing Zone layers (platform, connectivity, management) referencing the submodule modules locally.
3. Refactor `infra/main.bicep` so app resources depend on landing zone outputs (virtual network IDs, Log Analytics workspace, Key Vault, etc.).
4. Extend `azure.yaml` & parameter files to include new landing zone inputs (management group IDs, policy toggles, identity IDs).
5. Update docs (`docs/sample_app_setup.md`, `docs/local_environment_steps.md`) with new prerequisites.

### Phase 2 – Template Spec Packaging
1. Define template spec source structure under `infra/template-specs/` with metadata files per module (aligning with [Template Spec guidance](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/template-specs)).
2. Author automation script (Bash + Azure CLI) to build and publish template specs from submodule sources.
3. Create GitHub Actions workflow (or AZD pipeline stage) that authenticates, runs publish script, and stores template spec IDs as pipeline outputs/secrets.
4. Update orchestration Bicep to accept template spec IDs via parameters for deployment-time resolution.

### Phase 3 – Integration & Validation
1. Run linting (`bicep build`, `bicep linter`) against modified files and submodule references.
2. Deploy landing zone template specs to sandbox, capture outputs.
3. Deploy full solution (landing zone + sample app) using AZD or CLI, verifying networking, policies, AI Foundry, and sample app functionality.
4. Validate sample data indexing pipeline (`scripts/index_scripts/`) still functions with new network and security posture.

### Phase 4 – Hardening & Documentation
1. Incorporate feedback from validation, adjust parameter defaults and module composition.
2. Document operational processes (template spec refresh cadence, submodule updates, rollback strategy).
3. Update `README.md` high-level architecture diagram(s) to reflect landing zone inclusion.
4. Add CI job to check submodule version drift and enforce locked tag/commit.

## Risk & Mitigation Summary
- **Template Spec Drift**: Introduce automated tests that deploy template specs to a temporary RG to ensure compatibility before publishing.
- **RBAC & Policy Conflicts**: Pilot deployments in dedicated sandbox subscriptions; gate production rollout behind change management.
- **Submodule Maintenance**: Pin to specific tag/commit and schedule monthly review for upstream updates.
- **Deployment Complexity**: Provide composite deployment script (`deploy_landing_zone.sh`) that sequences template spec publish, landing zone deployment, and app deployment.

## Deliverables
- Updated repository structure with AI Landing Zone submodule.
- Orchestration Bicep bridging landing zone outputs to existing app workloads.
- Automated pipeline for template spec packaging/publishing.
- Documentation detailing deployment steps, parameter mappings, and operational processes.

## Next Steps
1. Review plan with stakeholders for scope confirmation and timeline approval.
2. Identify responsible engineers and assign phases.
3. Secure required Azure permissions and sandbox subscriptions.
4. Kick off Phase 0 discovery activities.
