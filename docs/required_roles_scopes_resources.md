# Required roles and scopes for deployment

This repository now deploys the AI Landing Zone submodule plus optional Fabric capacity, private endpoints, and PostgreSQL. The required access is driven by the role assignments defined in the submodule and the feature flags you enable (for example `deployContainerApps`, `deployAiFoundry`, `deployFabricCapacity`, `deployPostgreSql`).

## Minimum permissions

You need permissions to create resources and to write role assignments. The deployment assigns roles to the executor, container app identities, the AI Foundry project, Search, and (optionally) the jumpbox VM. That requires `Microsoft.Authorization/roleAssignments/write` at the resource scope.

- **Recommended (simplest):** `Owner` at the subscription scope.
- **Least privilege (typical):** `Contributor` + `User Access Administrator` at the subscription scope.
- **Existing resource group:** `Contributor` + `User Access Administrator` at the resource group scope.

If you cannot grant role assignments at the scope where resources are created, the deployment will fail when it attempts to assign RBAC roles.

## Role assignments created by the template

The full list of default role assignments is maintained in the AI Landing Zone submodule. These assignments change if you modify `containerAppsList` or disable services.

- Default role assignment matrix: [AI Landing Zone README](https://github.com/Azure/ai-landing-zone/blob/main/README.md)
- Default container app roles (driven by `containerAppsList`): [infra/main.bicepparam](../infra/main.bicepparam)

## Required resource providers

Register these providers in the subscription before deployment. Optional providers are only needed if the related feature flag is enabled.

| Provider | When used |
|---|---|
| Microsoft.Authorization | Role assignments (always) |
| Microsoft.CognitiveServices | AI Foundry account, projects, and connections (deployAiFoundry) |
| Microsoft.Search | Azure AI Search (deploySearchService) |
| Microsoft.Storage | Storage accounts and blob containers (deployStorageAccount) |
| Microsoft.KeyVault | Key Vault and secrets (deployKeyVault, deployVmKeyVault, PostgreSQL secrets) |
| Microsoft.ContainerRegistry | ACR (deployContainerRegistry) |
| Microsoft.App | Container Apps and environments (deployContainerApps, deployContainerEnv) |
| Microsoft.DocumentDB | Cosmos DB account and data-plane roles (deployCosmosDb) |
| Microsoft.ManagedIdentity | User-assigned identities (useUAI) |
| Microsoft.Insights | Application Insights and private link scopes (deployAppInsights) |
| Microsoft.OperationalInsights | Log Analytics (deployLogAnalytics) |
| Microsoft.Network | VNets, subnets, private endpoints, private DNS, Bastion, NAT (networkIsolation or deployVM) |
| Microsoft.Compute | Jumpbox VM and extensions (deployVM) |
| Microsoft.Bing | Bing grounding (deployGroundingWithBing) |
| Microsoft.Fabric | Fabric capacity and private link services (deployFabricCapacity, Fabric private endpoint) |
| Microsoft.DBforPostgreSQL | PostgreSQL Flexible Server (deployPostgreSql) |
