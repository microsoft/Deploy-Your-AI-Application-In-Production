# Using Fabric Private Networking Scripts in External Environments

This guide shows how to use the atomic Fabric private networking scripts in **external Azure environments** (outside of the full `azd` deployment).

## Three Ways to Provide Configuration

The scripts support **three configuration methods** with the following priority:

1. **Command-line parameters** (highest priority)
2. **Shell environment variables** (for external environments)
3. **azd environment** (for azd deployments)

---

## Method 1: Command-Line Parameters

**Best for:** One-off executions, testing, CI/CD pipelines

### Create DNS Zones
```powershell
./create_fabric_private_dns_zones.ps1 `
  -ResourceGroupName "rg-external-project" `
  -VirtualNetworkId "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-external-project/providers/Microsoft.Network/virtualNetworks/vnet-external" `
  -BaseName "external-project"
```

### Create Private Endpoint
```powershell
# First, ensure workspace ID is available
$env:FABRIC_WORKSPACE_ID = "a1b2c3d4-e5f6-7890-1234-567890abcdef"
$env:AZURE_RESOURCE_GROUP = "rg-external-project"
$env:AZURE_SUBSCRIPTION_ID = "12345678-1234-1234-1234-123456789012"
$env:AZURE_LOCATION = "eastus"
$env:AZURE_VNET_ID = "/subscriptions/.../virtualNetworks/vnet-external"
$env:FABRIC_CAPACITY_ID = "/subscriptions/.../Microsoft.Fabric/capacities/capacity-external"

./create_fabric_workspace_private_endpoint.ps1
```

---

## Method 2: Shell Environment Variables

**Best for:** Interactive sessions, development environments, persisted configuration

### Setup Environment Variables
```powershell
# PowerShell
$env:AZURE_RESOURCE_GROUP = "rg-external-project"
$env:AZURE_SUBSCRIPTION_ID = "12345678-1234-1234-1234-123456789012"
$env:AZURE_LOCATION = "eastus"
$env:AZURE_BASE_NAME = "external-project"
$env:AZURE_VNET_ID = "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-external-project/providers/Microsoft.Network/virtualNetworks/vnet-external"
$env:FABRIC_WORKSPACE_ID = "a1b2c3d4-e5f6-7890-1234-567890abcdef"
$env:FABRIC_CAPACITY_ID = "/subscriptions/.../Microsoft.Fabric/capacities/capacity-external"

# Optional: Auto-create DNS zones if missing
$env:FABRIC_AUTO_CREATE_DNS_ZONES = "true"

# Now run scripts without parameters
./create_fabric_private_dns_zones.ps1
./create_fabric_workspace_private_endpoint.ps1
```

### Bash Equivalent
```bash
# Bash
export AZURE_RESOURCE_GROUP="rg-external-project"
export AZURE_SUBSCRIPTION_ID="12345678-1234-1234-1234-123456789012"
export AZURE_LOCATION="eastus"
export AZURE_BASE_NAME="external-project"
export AZURE_VNET_ID="/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-external-project/providers/Microsoft.Network/virtualNetworks/vnet-external"
export FABRIC_WORKSPACE_ID="a1b2c3d4-e5f6-7890-1234-567890abcdef"
export FABRIC_CAPACITY_ID="/subscriptions/.../Microsoft.Fabric/capacities/capacity-external"
export FABRIC_AUTO_CREATE_DNS_ZONES="true"

# Run scripts
pwsh ./create_fabric_private_dns_zones.ps1
pwsh ./create_fabric_workspace_private_endpoint.ps1
```

---

## Method 3: azd Environment

**Best for:** Full azd deployments, automated workflows

### Setup azd Environment
```bash
# Initialize azd environment
azd env new external-project
azd env set AZURE_RESOURCE_GROUP "rg-external-project"
azd env set AZURE_SUBSCRIPTION_ID "12345678-1234-1234-1234-123456789012"
azd env set AZURE_LOCATION "eastus"
azd env set AZURE_ENV_NAME "external-project"
azd env set virtualNetworkId "/subscriptions/.../virtualNetworks/vnet-external"
azd env set FABRIC_WORKSPACE_ID "a1b2c3d4-e5f6-7890-1234-567890abcdef"
azd env set FABRIC_CAPACITY_ID "/subscriptions/.../Microsoft.Fabric/capacities/capacity-external"
azd env set FABRIC_AUTO_CREATE_DNS_ZONES "true"

# Run scripts (will read from azd environment)
./create_fabric_private_dns_zones.ps1
./create_fabric_workspace_private_endpoint.ps1
```

---

## Complete External Environment Example

**Scenario:** You have an existing Azure environment with:
- VNet deployed manually
- Fabric capacity already provisioned
- No azd deployment

### Step 1: Get Required Resource IDs

```bash
# Get VNet ID
VNET_ID=$(az network vnet show \
  --name vnet-external \
  --resource-group rg-external-project \
  --query id -o tsv)
echo "VNet ID: $VNET_ID"

# Get Fabric Capacity ID
CAPACITY_ID=$(az resource list \
  --resource-group rg-external-project \
  --resource-type "Microsoft.Fabric/capacities" \
  --query "[0].id" -o tsv)
echo "Capacity ID: $CAPACITY_ID"

# Get Subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo "Subscription ID: $SUBSCRIPTION_ID"
```

### Step 2: Create Fabric Workspace (if not exists)

```powershell
# Assuming you have a workspace creation script or use Fabric portal
# Export the workspace ID after creation
$workspaceId = "a1b2c3d4-e5f6-7890-1234-567890abcdef"  # From Fabric portal or API
```

### Step 3: Set Environment Variables

```powershell
# PowerShell
$env:AZURE_RESOURCE_GROUP = "rg-external-project"
$env:AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID
$env:AZURE_LOCATION = "eastus"
$env:AZURE_BASE_NAME = "external-project"
$env:AZURE_VNET_ID = $VNET_ID
$env:FABRIC_WORKSPACE_ID = $workspaceId
$env:FABRIC_CAPACITY_ID = $CAPACITY_ID
$env:FABRIC_AUTO_CREATE_DNS_ZONES = "true"
```

### Step 4: Run Atomic Scripts

```powershell
# Navigate to scripts directory
cd scripts/automationScripts/Fabric_Purview_Automation/

# Step 4.1: Create DNS zones
./create_fabric_private_dns_zones.ps1

# Expected output:
# [fabric-dns-zones] Creating Fabric Private DNS Zones
# [fabric-dns-zones] ✓ Resource Group: rg-external-project
# [fabric-dns-zones] ✓ VNet ID: /subscriptions/.../virtualNetworks/vnet-external
# [fabric-dns-zones] Zone: privatelink.analysis.windows.net
# [fabric-dns-zones]   ✓ DNS zone created
# [fabric-dns-zones]   ✓ VNet link created
# ... (2 more zones)
# [fabric-dns-zones] ✓ Fabric Private DNS Zones Configuration Complete

# Step 4.2: Create private endpoint
./create_fabric_workspace_private_endpoint.ps1

# Expected output:
# [fabric-private-endpoint] Creating Fabric Workspace Private Endpoint
# [fabric-private-endpoint] ✓ VNet deployed: Network isolated design
# [fabric-private-endpoint] ✓ Fabric capacity deployed: Private endpoint needed
# [fabric-private-endpoint] ✓ Workspace ID: a1b2c3d4-e5f6-7890-1234-567890abcdef
# [fabric-private-endpoint] ✓ Private endpoint created: pe-fabric-workspace-external-project
# [fabric-private-endpoint]   Private IP: 10.0.2.5
# [fabric-private-endpoint]   Connection State: Approved
# [fabric-private-endpoint] ✓ DNS zone group configured
# [fabric-private-endpoint] ✓ Fabric Workspace Private Endpoint Created Successfully
```

---

## Configuration Reference

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `AZURE_RESOURCE_GROUP` | Target resource group | `rg-external-project` |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID | `12345678-1234-...` |
| `AZURE_LOCATION` | Azure region | `eastus` |
| `AZURE_VNET_ID` | VNet resource ID | `/subscriptions/.../virtualNetworks/vnet-name` |
| `FABRIC_WORKSPACE_ID` | Fabric workspace GUID | `a1b2c3d4-e5f6-7890-...` |
| `FABRIC_CAPACITY_ID` | Fabric capacity resource ID | `/subscriptions/.../Microsoft.Fabric/capacities/...` |

### Optional Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AZURE_BASE_NAME` | Base name for resources | `fabric` |
| `FABRIC_AUTO_CREATE_DNS_ZONES` | Auto-create missing DNS zones | `false` |

---

## CI/CD Integration Examples

### GitHub Actions

```yaml
name: Deploy Fabric Private Networking

on:
  workflow_dispatch:
    inputs:
      workspace_id:
        description: 'Fabric Workspace ID'
        required: true

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Set Environment Variables
        run: |
          echo "AZURE_RESOURCE_GROUP=${{ secrets.AZURE_RESOURCE_GROUP }}" >> $GITHUB_ENV
          echo "AZURE_SUBSCRIPTION_ID=${{ secrets.AZURE_SUBSCRIPTION_ID }}" >> $GITHUB_ENV
          echo "AZURE_LOCATION=eastus" >> $GITHUB_ENV
          echo "AZURE_VNET_ID=${{ secrets.AZURE_VNET_ID }}" >> $GITHUB_ENV
          echo "FABRIC_WORKSPACE_ID=${{ github.event.inputs.workspace_id }}" >> $GITHUB_ENV
          echo "FABRIC_CAPACITY_ID=${{ secrets.FABRIC_CAPACITY_ID }}" >> $GITHUB_ENV
          echo "FABRIC_AUTO_CREATE_DNS_ZONES=true" >> $GITHUB_ENV
      
      - name: Create DNS Zones
        run: |
          pwsh ./scripts/.../create_fabric_private_dns_zones.ps1
      
      - name: Create Private Endpoint
        run: |
          pwsh ./scripts/.../create_fabric_workspace_private_endpoint.ps1
```

### Azure DevOps Pipeline

```yaml
trigger: none

parameters:
  - name: workspaceId
    displayName: 'Fabric Workspace ID'
    type: string

variables:
  - group: fabric-networking-vars  # Contains AZURE_* secrets

steps:
  - task: AzureCLI@2
    displayName: 'Create DNS Zones'
    inputs:
      azureSubscription: 'Azure Service Connection'
      scriptType: 'pscore'
      scriptLocation: 'scriptPath'
      scriptPath: './scripts/.../create_fabric_private_dns_zones.ps1'
    env:
      AZURE_RESOURCE_GROUP: $(AZURE_RESOURCE_GROUP)
      AZURE_SUBSCRIPTION_ID: $(AZURE_SUBSCRIPTION_ID)
      AZURE_VNET_ID: $(AZURE_VNET_ID)
      FABRIC_AUTO_CREATE_DNS_ZONES: 'true'

  - task: AzureCLI@2
    displayName: 'Create Private Endpoint'
    inputs:
      azureSubscription: 'Azure Service Connection'
      scriptType: 'pscore'
      scriptLocation: 'scriptPath'
      scriptPath: './scripts/.../create_fabric_workspace_private_endpoint.ps1'
    env:
      AZURE_RESOURCE_GROUP: $(AZURE_RESOURCE_GROUP)
      AZURE_SUBSCRIPTION_ID: $(AZURE_SUBSCRIPTION_ID)
      AZURE_LOCATION: 'eastus'
      AZURE_VNET_ID: $(AZURE_VNET_ID)
      FABRIC_WORKSPACE_ID: ${{ parameters.workspaceId }}
      FABRIC_CAPACITY_ID: $(FABRIC_CAPACITY_ID)
```

---

## Troubleshooting

### Error: "ResourceGroupName is required"

**Cause:** No configuration method provided values

**Solution:** Set environment variables or use command-line parameters:
```powershell
$env:AZURE_RESOURCE_GROUP = "rg-external-project"
./create_fabric_private_dns_zones.ps1
```

### Error: "VNet not deployed - skipping"

**Cause:** `AZURE_VNET_ID` or `virtualNetworkId` not set

**Solution:** This is normal if you're not using network isolation. To force execution:
```powershell
$env:AZURE_VNET_ID = "/subscriptions/.../virtualNetworks/vnet-name"
./create_fabric_workspace_private_endpoint.ps1
```

### Error: "FABRIC_WORKSPACE_ID not found"

**Cause:** Workspace must be created before private endpoint

**Solution:** Create workspace first and export ID:
```powershell
# Option 1: From Fabric portal - copy workspace ID
$env:FABRIC_WORKSPACE_ID = "workspace-guid-from-portal"

# Option 2: From workspace creation script
./create_fabric_workspace.ps1
# (script exports FABRIC_WORKSPACE_ID automatically)
```

---

## Best Practices

1. **Use environment variables for CI/CD**: Easier to manage secrets and configuration
2. **Use command-line parameters for testing**: Quick one-off executions
3. **Use azd environment for full deployments**: Consistent with main deployment pattern
4. **Enable auto-create flag**: `FABRIC_AUTO_CREATE_DNS_ZONES=true` for self-healing
5. **Validate prerequisites**: Check VNet, capacity, and workspace exist before running scripts
6. **Store resource IDs**: Save VNet ID, capacity ID in CI/CD variables for reuse

---

## Summary

The atomic Fabric private networking scripts are **fully portable** and work in any Azure environment:

- ✅ No azd dependency required
- ✅ Three configuration methods supported
- ✅ Graceful error handling with helpful messages
- ✅ Idempotent (safe to re-run)
- ✅ CI/CD friendly
- ✅ Self-healing with auto-create flag

Choose the configuration method that best fits your workflow!
