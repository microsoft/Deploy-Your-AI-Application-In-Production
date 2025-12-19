# OneLake Indexing Scripts

This folder contains scripts for automating OneLake document indexing with Azure AI Search. These scripts are designed to be executed in sequence as part of the Azure deployment process.

## Script Execution Order

The scripts are numbered and should be executed in the following order:

### 1. `01_create_onelake_skillsets.ps1`
- **Purpose**: Creates AI Search skillsets required for processing OneLake documents
- **Creates**: `onelake-textonly-skillset` with text splitting capabilities
- **API Version**: Uses `2024-05-01-preview` (required for OneLake)
- **Dependencies**: None

### 2. `02_create_onelake_datasource.ps1`
- **Purpose**: Creates OneLake data source connection in AI Search
- **Creates**: OneLake data source with System-Assigned Managed Identity authentication
- **Connection**: Uses `ResourceId={workspaceId}` format as per Microsoft documentation
- **Dependencies**: AI Search service with System-Assigned Managed Identity

### 3. `03_create_onelake_indexer.ps1`
- **Purpose**: Creates and runs the OneLake indexer to process documents
- **Creates**: Indexer that processes documents from OneLake into the search index
- **Execution**: Automatically runs the indexer and reports results
- **Dependencies**: Skillset and data source from previous scripts

### 4. `04_debug_onelake_indexer.ps1`
- **Purpose**: Diagnostic script for troubleshooting OneLake indexing issues
- **Use Case**: Run manually when indexers are not finding documents
- **Reports**: Detailed status, errors, warnings, and configuration information

## Configuration Requirements

### Environment Variables
```bash
FABRIC_WORKSPACE_ID='your-workspace-id'    # Required
FABRIC_LAKEHOUSE_ID='your-lakehouse-id'    # Required
AZURE_AI_SEARCH_NAME='your-ai-search-service'                 # Set by infra
AZURE_RESOURCE_GROUP_NAME='your-resource-group'               # Set by infra
AZURE_SUBSCRIPTION_ID='your-subscription-id'                  # Set by infra
```

### Critical Configuration Format
**IMPORTANT**: Based on successful portal configuration analysis:

```json
{
  "credentials": {
    "connectionString": "ResourceId=WORKSPACE_ID"  // Not lakehouse ID!
  },
  "container": {
    "name": "LAKEHOUSE_ID",                        // The lakehouse GUID
    "query": null                                  // null - let indexer scan all folders
  }
}
```

**Key Points**:
- ✅ Connection string uses **workspace ID**  
- ✅ Container name uses **lakehouse ID**
- ✅ Query should be **null** (not a specific folder path)
- ✅ API version **must be** `2024-05-01-preview`

## Key Technical Requirements

### API Version
- **CRITICAL**: All scripts use `2024-05-01-preview` API version
- OneLake indexing is NOT supported in stable API versions
- Using wrong API version will result in 400 Bad Request errors

### Authentication
- Uses System-Assigned Managed Identity (SAMI)
- No `identity` field in JSON (per Microsoft documentation)
- Connection string format: `ResourceId={workspaceGuid}`

### Permissions Required
The AI Search System-Assigned Managed Identity must have:

1. **Fabric Permissions**: OneLake data access role in the Fabric workspace
2. **Azure Permissions**: Storage Blob Data Reader role

## Integration with azure.yaml

These scripts are automatically executed as part of the `postprovision` hooks in azure.yaml:

```yaml
hooks:
  postprovision:
    # ... other scripts ...
    - run: ./scripts/OneLakeIndex/01_create_onelake_skillsets.ps1
      interactive: false
      shell: pwsh
    - run: ./scripts/OneLakeIndex/02_create_onelake_datasource.ps1
      interactive: false
      shell: pwsh
    - run: ./scripts/OneLakeIndex/03_create_onelake_indexer.ps1
      interactive: false
      shell: pwsh
    # ... other scripts ...
```

## Troubleshooting

### Common Issues



### Manual Execution

To run scripts manually:

```powershell
cd /workspaces/fabric-purview-domain-integration

# Set environment variables
$env:AZURE_AI_SEARCH_NAME = "your-search-service"
$env:AZURE_RESOURCE_GROUP_NAME = "your-resource-group"
$env:AZURE_SUBSCRIPTION_ID = "your-subscription-id"
$env:FABRIC_WORKSPACE_ID = "your-workspace-guid"
$env:FABRIC_LAKEHOUSE_ID = "your-lakehouse-guid"

# Execute in order
./scripts/OneLakeIndex/01_create_onelake_skillsets.ps1
./scripts/OneLakeIndex/02_create_onelake_datasource.ps1
./scripts/OneLakeIndex/03_create_onelake_indexer.ps1

# For debugging
./scripts/OneLakeIndex/04_debug_onelake_indexer.ps1
```

## Success Indicators

- ✅ Skillset created successfully
- ✅ Data source created successfully  
- ✅ Indexer created and runs with `success` status
- ✅ Items processed > 0
- ✅ Documents appear in the search index

If all scripts complete successfully but items processed = 0, the issue is typically with managed identity permissions in Microsoft Fabric.
