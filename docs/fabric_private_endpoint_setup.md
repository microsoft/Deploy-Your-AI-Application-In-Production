# Fabric Workspace Private Endpoint Setup

## Overview

This guide explains how to configure private endpoint access to Microsoft Fabric workspaces from Azure VNet resources (e.g., Jump VM). This enables secure, private access to Fabric when tenant-level private link is enabled.

## Architecture

```
Jump VM → Private Endpoint → Fabric Workspace
   ↓
Private DNS Zones (privatelink.analysis.windows.net, etc.)
   ↓
Fabric Portal & Services (private access only)
```

## Prerequisites

1. **Fabric Capacity deployed** (`deployToggles.fabricCapacity = true`)
2. **Fabric Workspace created** (via `create_fabric_workspace.ps1`)
3. **VNet and Jump VM deployed**
4. **Azure permissions**:
   - Contributor or Network Contributor on resource group
   - Fabric Workspace Admin on the workspace
   - Power Platform Admin or Global Admin (to enable tenant-level private link)

## Automated Setup

### Step 1: Enable Private Endpoint Toggle

Edit `infra/main-orchestrator.bicep` or `infra/main-orchestrator.bicepparam`:

```bicep
param deployToggles object = {
  // ... other toggles ...
  fabricCapacity: true
  fabricPrivateEndpoint: true  // Enable this
}
```

### Step 2: Deploy Infrastructure

```bash
azd up
```

This will:
- ✅ Create private DNS zones for Fabric (`privatelink.analysis.windows.net`, etc.)
- ✅ Link DNS zones to your VNet
- ✅ Prepare infrastructure for private endpoint (created in Step 4)

### Step 3: Create Fabric Workspace

Run the post-provision script (happens automatically):

```powershell
./scripts/automationScripts/Fabric_Purview_Automation/create_fabric_workspace.ps1
```

### Step 4: Set Up Private Endpoint

Run the private endpoint setup script:

```powershell
./scripts/postprovision/setup_workspace_private_endpoint.ps1
```

This script will:
1. ✅ Get Fabric workspace ID
2. ✅ Enable workspace-level private link
3. ✅ Create private endpoint in jumpbox-subnet
4. ✅ Configure private DNS zones
5. ✅ Set workspace to deny public access (allow only private endpoint)

### Step 5: Enable Tenant-Level Private Link

In Fabric Admin Portal:
1. Go to https://app.fabric.microsoft.com
2. Click **⚙️ Settings** → **Admin portal**
3. **Tenant settings** → **Advanced networking**
4. **Enable "Tenant-level Private Link"**
5. Click **Apply**

⚠️ **Wait 30 minutes** for policy changes to propagate.

### Step 6: Test Access

1. Connect to Jump VM via Bastion
2. Open browser in Jump VM
3. Navigate to `https://app.powerbi.com` or `https://app.fabric.microsoft.com`
4. Verify you can access the Fabric workspace

## Manual Steps (If Automation Fails)

### Enable Workspace-Level Private Link

If the script cannot enable workspace-level private link automatically:

1. Go to https://app.fabric.microsoft.com
2. Open your workspace
3. **Workspace Settings** → **Security** → **Private Link**
4. Enable **"Workspace-level private link"**
5. Click **Apply**

### Approve Private Endpoint Connection

If the connection is pending approval:

1. Go to https://app.fabric.microsoft.com
2. Open your workspace
3. **Workspace Settings** → **Security** → **Private Link** → **Private Endpoints**
4. Find the pending connection
5. Click **Approve**

### Configure Workspace to Deny Public Access

If the script cannot set the communication policy:

1. Go to https://app.fabric.microsoft.com
2. Open your workspace
3. **Workspace Settings** → **Inbound networking**
4. Select **"Allow connections only from workspace level private links"**
5. Click **Apply**

## Verification

### Check Private Endpoint Status

```bash
az network private-endpoint show \
  --name pe-fabric-workspace-{baseName} \
  --resource-group rg-{env} \
  --query "privateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status" \
  -o tsv
```

**Expected**: `Approved`

### Check DNS Resolution from Jump VM

From Jump VM PowerShell:

```powershell
Resolve-DnsName app.powerbi.com
```

**Expected**: Should resolve to a private IP (192.168.x.x range)

### Check Workspace Communication Policy

```powershell
$workspaceId = "your-workspace-id"
$token = "your-fabric-api-token"

Invoke-RestMethod `
  -Uri "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/networking/communicationPolicy" `
  -Headers @{Authorization="Bearer $token"} `
  -Method Get
```

**Expected**: `defaultAction: "Deny"` (public access blocked)

## Troubleshooting

### Issue: DNS_PROBE_FINISHED_NXDOMAIN when accessing Fabric

**Cause**: Private DNS zones exist but no A records (private endpoint not created)

**Solution**:
1. Run `setup_workspace_private_endpoint.ps1`
2. Or delete empty DNS zones if not using private endpoints:
   ```bash
   az network private-dns zone delete --name privatelink.analysis.windows.net --resource-group rg-{env}
   ```

### Issue: Connection Pending Approval

**Cause**: Private endpoint requires manual approval in Fabric portal

**Solution**: Follow manual approval steps above

### Issue: Can't Access Fabric After Enabling Tenant-Level Private Link

**Cause**: Policy changes take time to propagate (up to 30 minutes)

**Solution**: Wait 30 minutes, then test again

### Issue: Script Fails with "Workspace not found"

**Cause**: Workspace hasn't been created yet

**Solution**: Run `create_fabric_workspace.ps1` first

### Issue: Script Fails with "Access Denied"

**Cause**: Insufficient permissions

**Solution**: Ensure you have:
- Fabric Workspace Admin role on the workspace
- Contributor role on Azure resource group
- Power Platform Admin or Global Admin (for tenant settings)

## Architecture Details

### Private Endpoint Flow

1. **Jump VM** sends request to `app.powerbi.com`
2. **Private DNS Zone** resolves to private endpoint IP (192.168.x.x)
3. **Private Endpoint** forwards request to Fabric workspace
4. **Fabric Workspace** validates connection is from approved private endpoint
5. **Response** returns through private channel

### DNS Zones Required

- `privatelink.analysis.windows.net` - Fabric Analysis Services (portal access)
- `privatelink.pbidedicated.windows.net` - Fabric Capacity
- `privatelink.prod.powerquery.microsoft.com` - Power Query (data integration)

### Network Security

With private endpoint configured:
- ✅ **Jump VM** → Fabric: Private connection through VNet
- ❌ **Public Internet** → Fabric: Blocked (when tenant-level private link enabled)
- ✅ **On-Premises** → Fabric: Via VPN/ExpressRoute to VNet

## Cost Considerations

- **Private Endpoint**: ~$0.01/hour (~$7.30/month)
- **Private DNS Zones**: $0.50/zone/month (~$1.50/month for 3 zones)
- **Data Processing**: $0.01/GB (for traffic through private endpoint)

**Total estimated cost**: ~$9-10/month

## Cleanup

To remove private endpoint and allow public access again:

```bash
# Delete private endpoint
az network private-endpoint delete \
  --name pe-fabric-workspace-{baseName} \
  --resource-group rg-{env}

# Delete DNS zones (optional)
az network private-dns zone delete --name privatelink.analysis.windows.net --resource-group rg-{env}
az network private-dns zone delete --name privatelink.pbidedicated.windows.net --resource-group rg-{env}
az network private-dns zone delete --name privatelink.prod.powerquery.microsoft.com --resource-group rg-{env}

# Disable tenant-level private link in Fabric Admin Portal
```

## References

- [Azure Private Endpoint Documentation](https://learn.microsoft.com/azure/private-link/private-endpoint-overview)
- [Fabric Private Link Documentation](https://learn.microsoft.com/fabric/security/security-private-links-overview)
- [Fabric Workspace Settings](https://learn.microsoft.com/fabric/admin/workspace-settings)
