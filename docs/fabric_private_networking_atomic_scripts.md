# Fabric Private Networking - Atomic Scripts

This document explains the atomic script architecture for Fabric private endpoint deployment. These scripts live under `scripts/automationScripts/FabricWorkspace/SecureWorkspace`.

## Architecture Philosophy

The Fabric private networking scripts follow the **Unix philosophy**:
- ✅ Each script does one thing well
- ✅ Scripts work together via environment variables
- ✅ Scripts handle missing prerequisites gracefully
- ✅ Scripts can be run independently or as part of automation

## Scripts Overview

### 1. `create_fabric_private_dns_zones.ps1`
**Purpose:** Create Azure Private DNS zones required for Fabric private endpoints

**What it does:**
- Creates 3 DNS zones:
  - `privatelink.analysis.windows.net` (Fabric portal/Power BI)
  - `privatelink.pbidedicated.windows.net` (Fabric capacity)
  - `privatelink.prod.powerquery.microsoft.com` (Power Query)
- Links zones to VNet for private DNS resolution
- Skips creation if zones already exist (idempotent)

**When to use:**
- External Azure environments (not using full Bicep deployment)
- Environments where stage 7 wasn't deployed
- Manual DNS zone setup scenarios

**Usage:**
```powershell
# Standalone usage
./create_fabric_private_dns_zones.ps1 `
  -ResourceGroupName "rg-myproject" `
  -VirtualNetworkId "/subscriptions/.../virtualNetworks/vnet-myproject" `
  -BaseName "myproject"

# Or let it read from azd environment
azd env set AZURE_RESOURCE_GROUP "rg-myproject"
azd env set virtualNetworkId "/subscriptions/.../virtualNetworks/vnet-myproject"
./create_fabric_private_dns_zones.ps1
```

### 2. `create_fabric_workspace_private_endpoint.ps1`
**Purpose:** Create private endpoint for Fabric workspace in VNet

**What it does:**
- Checks if private endpoint is needed (VNet + Fabric capacity deployed)
- Creates private endpoint in jumpbox subnet
- Automatically calls DNS zone script if `FABRIC_AUTO_CREATE_DNS_ZONES=true`
- Links private endpoint to DNS zones
- Gracefully exits if prerequisites not met

**When to use:**
- After Fabric workspace is created (`FABRIC_WORKSPACE_ID` available)
- In network-isolated deployments
- When VNet and Fabric capacity are both deployed

**Usage:**
```powershell
# Automatic usage (in azd post-provision)
# Prerequisites: Workspace created, FABRIC_WORKSPACE_ID exported
./create_fabric_workspace_private_endpoint.ps1

# With auto-DNS creation
azd env set FABRIC_AUTO_CREATE_DNS_ZONES "true"
./create_fabric_workspace_private_endpoint.ps1

# Standalone usage in external environment
azd env set FABRIC_WORKSPACE_ID "12345678-1234-1234-1234-123456789012"
azd env set AZURE_RESOURCE_GROUP "rg-myproject"
azd env set AZURE_SUBSCRIPTION_ID "..."
azd env set virtualNetworkId "..."
./create_fabric_workspace_private_endpoint.ps1
```

## Deployment Scenarios

### Scenario 1: Full Bicep Deployment (Default)
**Flow:**
1. `azd up` → Bicep deploys infrastructure
2. Stage 7 (Bicep) → DNS zones created ✓
3. Post-provision stage 3.4 → DNS zone script runs (skips - already exist)
4. Post-provision stage 3.5 → Private endpoint created ✓

**Result:** Fully automated, no manual steps

---

### Scenario 2: External Environment (No Bicep)
**Flow:**
1. User has existing VNet in Azure
2. User runs `create_fabric_workspace.ps1` → Workspace created
3. User exports workspace ID: `azd env set FABRIC_WORKSPACE_ID "..."`
4. User runs `create_fabric_private_dns_zones.ps1` → DNS zones created ✓
5. User runs `create_fabric_workspace_private_endpoint.ps1` → Private endpoint created ✓

**Result:** Manual orchestration, but atomic scripts handle each step

---

### Scenario 3: Auto-Create DNS Zones
**Flow:**
1. Bicep deployment without stage 7 (network isolated but no DNS zones)
2. Post-provision stage 3.5 with `FABRIC_AUTO_CREATE_DNS_ZONES=true`
3. Private endpoint script detects missing zones
4. Automatically calls DNS zone script
5. Both DNS zones and private endpoint created ✓

**Result:** Self-healing automation

---

### Scenario 4: Public Workspace (No Network Isolation)
**Flow:**
1. `azd up` with `virtualNetwork: false` or `fabricCapacity: false`
2. Private endpoint script checks conditions
3. Gracefully exits with info message ✓

**Result:** No errors, no unnecessary resources

## Environment Variables

### Required (from azd environment)
- `FABRIC_WORKSPACE_ID` - Fabric workspace GUID (from `create_fabric_workspace.ps1`)
- `AZURE_RESOURCE_GROUP` - Target resource group
- `AZURE_SUBSCRIPTION_ID` - Azure subscription ID
- `AZURE_LOCATION` - Azure region
- `virtualNetworkId` - VNet resource ID (for network isolation)

### Optional (configuration)
- `FABRIC_AUTO_CREATE_DNS_ZONES` - Set to `"true"` to auto-create missing DNS zones
- `AZURE_ENV_NAME` - Base name for resources (defaults to `"fabric"`)

## Integration with Bicep

### Stage 7: Fabric Private Networking (Bicep)
**Conditional deployment:**
```bicep
module fabricNetworking = if (deployToggles.virtualNetwork && deployToggles.fabricCapacity) {
  name: 'deploy-fabric-networking'
  params: {
    deployPrivateDnsZones: true  // Creates DNS zones
  }
}
```

**What it deploys:**
- Private DNS zones (if `deployPrivateDnsZones: true`)
- VNet links for DNS zones
- DNS zone group configuration

**Relationship to scripts:**
- If stage 7 runs → DNS zones exist → scripts skip creation
- If stage 7 skipped → Scripts can create DNS zones via CLI

## Conditional Logic Summary

### Bicep (Stage 7)
```
Deploy DNS zones IF (virtualNetwork AND fabricCapacity)
```

### PowerShell (Private Endpoint Script)
```
Create private endpoint IF:
  1. virtualNetworkId exists (network isolated design)
  AND
  2. FABRIC_CAPACITY_ID exists (Fabric deployed)
```

### PowerShell (DNS Zone Script)
```
Create DNS zones IF:
  1. Zones don't already exist
  AND
  2. VirtualNetworkId provided (for linking)
```

## Best Practices

1. **For full deployments:** Use Bicep stage 7 (preferred)
   - Proper Azure resource management
   - Supports updates/changes
   - Automatic VNet linking

2. **For external environments:** Use atomic scripts
   - Create DNS zones first (prerequisite)
   - Create private endpoint second
   - Both scripts are idempotent (safe to re-run)

3. **For automation:** Use `FABRIC_AUTO_CREATE_DNS_ZONES=true`
   - Self-healing if DNS zones missing
   - No manual intervention required

4. **For testing:** Run scripts independently
   - Each script has clear prerequisites
   - Graceful error handling
   - Detailed logging

## Troubleshooting

### DNS zones not found
**Symptom:** Warning: "DNS zone not found: privatelink.analysis.windows.net"

**Solutions:**
1. Run `create_fabric_private_dns_zones.ps1` manually
2. Set `FABRIC_AUTO_CREATE_DNS_ZONES=true` and re-run
3. Deploy via Bicep stage 7

### Private endpoint creation fails
**Symptom:** Error: "Failed to create private endpoint"

**Check:**
1. Workspace ID exported? `azd env get-values | grep FABRIC_WORKSPACE_ID`
2. VNet deployed? `azd env get-values | grep virtualNetworkId`
3. Capacity deployed? `azd env get-values | grep FABRIC_CAPACITY_ID`
4. Subnet exists? `az network vnet subnet show --name jumpbox-subnet ...`

### Script skips execution
**Symptom:** "VNet not deployed - skipping"

**This is normal!** The script detected:
- No VNet (public access mode), OR
- No Fabric capacity (nothing to create endpoint for)

This is **graceful degradation**, not an error.

## Summary

The atomic script architecture provides:
- ✅ **Flexibility**: Use in any Azure environment
- ✅ **Automation**: Self-healing with auto-create flag
- ✅ **Reusability**: Each script works independently
- ✅ **Reliability**: Idempotent, graceful error handling
- ✅ **Maintainability**: Clear separation of concerns

Choose your deployment path based on your scenario:
- **Full control?** → Use Bicep (stage 7)
- **External environment?** → Use atomic scripts
- **Quick deployment?** → Enable auto-create flag
- **Testing/debugging?** → Run scripts manually
