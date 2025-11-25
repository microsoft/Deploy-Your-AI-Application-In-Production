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
