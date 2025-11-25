# Frequently Asked Questions

## How do Azure AI Foundry account and project identities interact with Azure AI Search RBAC?

Fabric/Azure AI Foundry creates **separate managed identities** for the Foundry account and for each project. Azure RBAC permissions do **not** cascade from the account to its projects, so a role assignment that targets the account identity does not automatically grant the same access to the project identity.

The post-provision script `scripts/automationScripts/OneLakeIndex/06_setup_ai_foundry_search_rbac.ps1` therefore resolves **both** identities:

- `aiFoundryIdentity` → the AI Foundry **account** managed identity
- `projectPrincipalId` → the AI Foundry **project** managed identity

It then assigns the required Azure AI Search roles to every principal it finds. If the script cannot resolve the project identity, it logs a warning and only the account identity receives the roles. In that case, re-run the script once the project identity exists or assign the roles manually.

To verify the project identity has the right permissions, run:

```bash
# Retrieve the project managed identity principal ID
az resource show \
  --ids /subscriptions/<subscription>/resourceGroups/<resource-group>/providers/Microsoft.CognitiveServices/accounts/<account>/projects/<project> \
  --query "identity.principalId"

# Confirm role assignments on the AI Search service
searchScope="/subscriptions/<subscription>/resourceGroups/<resource-group>/providers/Microsoft.Search/searchServices/<search-service>"
az role assignment list --assignee <project-principal-id> --scope "$searchScope" \
  --query "[].roleDefinitionName"
```

The output should include:

- `Search Service Contributor`
- `Search Index Data Contributor` (or `Search Index Data Reader` if you only need read-only access)

If either role is missing, add it manually:

```bash
az role assignment create \
  --assignee <project-principal-id> \
  --role "Search Service Contributor" \
  --scope "$searchScope"

az role assignment create \
  --assignee <project-principal-id> \
  --role "Search Index Data Contributor" \
  --scope "$searchScope"
```

Because the knowledge source uses the **project** identity when it ingests data, those roles must be granted to the project principal even if the account identity already has them.

## How do I integrate an existing Azure AI Foundry project into the AI Landing Zone?

Integrating the new Azure AI Foundry project model (Cognitive Services account plus project announced at Ignite) into an AI Landing Zone is a matter of extending the landing zone controls so the project runs entirely inside the isolated estate. Work through these considerations:

1. **Locate the project**: Record the account and project resource IDs, region, and tenant. Confirm the region aligns with the landing zone virtual network and private DNS footprint so private endpoints can be created without cross-region limitations.
2. **Carve out network space**: Add a dedicated subnet (or set of subnets) in the landing zone virtual network for the Foundry managed network. Apply the landing zone NSG, UDR, and firewall baselines. If the project already uses managed network isolation, update it to target the new subnet; otherwise plan for a fresh isolated project and migrate assets with export/import tooling.
3. **Bring dependencies private**: For every service the project consumes (Azure AI Search, Storage, Key Vault, App Configuration, Cosmos DB, etc.), provision or reuse private endpoints in the landing zone subnet and link the associated private DNS zones to both the landing zone VNet and the Foundry managed subnet. Validate DNS resolution from that subnet before switching project connections to private FQDNs.
4. **Assign least privilege**: The updated architecture surfaces separate managed identities for the account and each project. Grant only the required RBAC roles (for example, `Search Service Contributor` plus `Search Index Data Reader` on search and `Storage Blob Data Reader` on storage) to both identities as needed, and double-check that Defender or conditional access policies in the landing zone allow them to authenticate.
5. **Control outbound access**: Align the project managed outbound configuration with the landing zone egress model by allowing only the Microsoft service tags and explicit endpoints the project requires, forcing all other traffic through the landing zone firewall or NVA.
6. **Validate end to end**: Use Azure AI Studio diagnostics to confirm private endpoint reachability, DNS resolution, role assignments, and content ingestion. Re-run prompt flows, indexing pipelines, and other workloads to ensure they operate entirely within the landing zone boundaries.

## What is the recommended migration approach when moving to the landing-zone project?

Follow these steps to migrate assets from an existing project into the landing-zone instance:

- **Export configuration**: Capture project metadata, workspace settings, prompt catalogs, content filters, evaluation templates, and managed endpoints with `az cognitiveservices account project export` (preview) or an ARM template export. Back up deployment policies and rate-limit settings.
- **Move custom models**: Download fine-tuned model artifacts from Azure AI Studio > Models or via the Foundry REST APIs, including versions, tokenizer configs, and training logs. Re-run the training jobs in the landing-zone project so lineage and monitoring start fresh.
- **Rebuild data connections**: Enumerate Cognitive Services connections, Key Vault references, search indexes, and storage links. Re-create matching private endpoints, DNS links, and connection objects in the landing-zone project, preferring managed identities over secrets.
- **Reapply automation**: Update Git-connected prompt flows and CI/CD pipelines (Azure DevOps or GitHub Actions) with the new project resource IDs, environment variables, and service connections, then replay the promotion pipelines to redeploy assets.
- **Verify and cut over**: Execute validation notebooks or automated smoke tests, confirm service quotas and feature flags match expectations, disable traffic on the old project, and repoint DNS or clients to the new endpoints.

**Next steps**

1. Inventory current project assets (models, flows, evaluations, connections) so nothing is missed.
2. Provision the isolated landing-zone project with required private endpoints and RBAC.
3. Run export/import scripts, validate workloads, and plan the production cutover once tests succeed.

## How do I initialize or refresh the AI Landing Zone submodules?

Run the repo-provided Git submodules command from the repository root:

```bash
cd /workspaces/Deploy-Your-AI-Application-In-Production && git submodule update --init --recursive
```

This syncs every nested submodule to the commit pinned by the main repository, ensuring the infrastructure and automation modules stay aligned. For more background, see Microsoft Learn resources on the [AI landing zone architecture](https://learn.microsoft.com/azure/cloud-adoption-framework/scenarios/ai/ai-landing-zone) and [working with Git submodules](https://learn.microsoft.com/azure/devops/repos/git/git-submodules).
