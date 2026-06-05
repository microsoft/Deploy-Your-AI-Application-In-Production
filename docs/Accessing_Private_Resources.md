# Accessing Private Resources

## Overview

This deployment uses **private endpoints** for all services, which means they have **no public network access**. This is the recommended security posture for production workloads.

To access these private resources, the deployment includes:
- ✅ **Azure Bastion** - Secure browser-based access to VMs
- ✅ **Jump VM (Windows)** - Management VM inside the virtual network

## How to Access Private Resources

### 1. Connect to Jump VM via Bastion (Microsoft Entra ID sign-in)

The jumpbox VM is provisioned with the **AAD Login for Windows** extension and the deploying
principal is automatically granted the **Virtual Machine Administrator Login** role on the VM.
Azure Bastion is deployed using the **Standard** SKU (which supports Microsoft Entra ID
authentication for Azure portal RDP/SSH sessions).

You sign in to the jumpbox with your **Microsoft Entra ID** credentials — there is **no local
username/password to manage**.

```text
# In the Azure Portal:
# 1. Navigate to your resource group
# 2. Open the jump VM (name starts with "testvm")
# 3. Click "Connect" -> "Bastion"
# 4. In the Bastion connection blade:
#       Authentication type: "Microsoft Entra ID"
#       Protocol:            RDP
#    (No username / password fields will be required.)
# 5. Click "Connect" - a browser tab opens with the RDP session,
#    signed in as your Entra ID user.
```

> **Note:** To grant additional users access, assign one of the following RBAC roles to them
> on the jump VM (or the resource group):
> - **Virtual Machine Administrator Login** - sign in with local administrator privileges
> - **Virtual Machine User Login** - sign in as a standard user
>

> A local admin account is still
> created on the VM because Windows requires one at provisioning time, but its password is
> auto-generated, never displayed, and **not** used to connect through Bastion.

### 2. From Jump VM, Access Private Services

Once connected to the Jump VM, you can:

- **Key Vault**: Access via Azure Portal or Azure CLI
- **Cosmos DB**: Connect using Data Explorer in Azure Portal
- **Azure AI Search**: Manage indexes via Azure Portal
- **Storage Account**: Browse blobs via Azure Portal or Storage Explorer
- **Container Registry**: Push/pull images using Docker CLI
- **Microsoft Foundry**: Manage projects and deployments

### 3. Install Tools on Jump VM (Optional)

For enhanced productivity, install these tools on the Jump VM:

```powershell
# Install Azure CLI
Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'

# Install Azure Storage Explorer
# Download from: https://azure.microsoft.com/features/storage-explorer/

# Install VS Code
# Download from: https://code.visualstudio.com/
```

## Alternative Access Methods

### Option 1: VPN Connection (Not Included)

For production environments, consider:
- Azure VPN Gateway for site-to-site connectivity
- Point-to-Site VPN for individual users
- ExpressRoute for dedicated private connection

To enable VPN, you would need to:
1. Deploy VPN Gateway in your VNet
2. Configure client certificates or AAD authentication
3. Connect from your local machine

### Option 2: Build VM (For CI/CD)

If you need CI/CD access to private resources:

1. **Enable Build VM** in `infra/main.bicepparam`:
   ```bicep
   buildVm: true                    // Linux Build VM (for CI/CD)
   devopsBuildAgentsNsg: true       // Required NSG
   ```

2. **Add subnet** to `vNetDefinition`:
   ```bicep
   {
     name: 'snet-build-agents'
     addressPrefix: '10.0.7.0/28'
   }
   ```

3. **Self-hosted agents** can then access private resources directly

### Option 3: Disable Private Endpoints (NOT Recommended)

⚠️ **Not recommended for production** - but for development/testing only:

You can configure services without private endpoints by modifying individual service definitions. However, this significantly reduces security posture.

## Costs

### What You're Paying For:

| Resource | Monthly Cost (Estimate) | Why Needed |
|----------|------------------------|------------|
| Azure Bastion Basic | ~$140 | Secure access to Jump VM |
| Jump VM (Standard B2s) | ~$35 | Management access to private resources |
| **Total** | **~$175/month** | **Required for private network access** |

### Cost Optimization Options:

1. **Bastion Basic vs Standard**:
   - Basic: $140/month, up to 25 concurrent sessions
   - Standard: $310/month, unlimited sessions + more features

2. **Jump VM Size**:
   - B2s (2 vCPUs, 4GB): ~$35/month (current default)
   - B1s (1 vCPU, 1GB): ~$10/month (minimal usage)
   - B4ms (4 vCPUs, 16GB): ~$140/month (heavy usage)

3. **Stop Jump VM When Not in Use**:
   ```bash
   # Stop VM to save compute costs (you only pay for storage)
   az vm deallocate --resource-group <rg> --name <vm-name>
   
   # Start when needed
   az vm start --resource-group <rg> --name <vm-name>
   ```
   **Savings**: ~$35/month when stopped (you still pay for Bastion + disk)

4. **Remove Bastion + Jump VM for Development**:
   
   ⚠️ **Only for non-production environments where security is not critical**
   
   Set in `infra/main.bicepparam`:
   ```bicep
   bastionHost: false
   jumpVm: false
   bastionNsg: false
   jumpboxNsg: false
   ```
   
   Remove subnets from `vNetDefinition`:
   ```bicep
   // Remove: AzureBastionSubnet
   // Remove: snet-jumpbox
   ```
   
   **Savings**: ~$175/month  
   **Trade-off**: Cannot access private resources; must configure public access

## Security Best Practices

1. **Use Bastion for Jump VM access** - Never expose RDP/SSH ports publicly
2. **Enable Just-In-Time (JIT) access** - Limit when the Jump VM can be accessed
3. **Use managed identities** - Avoid storing credentials on the Jump VM
4. **Enable MFA** - Require multi-factor authentication for Bastion access
5. **Monitor access** - Review Bastion connection logs in Log Analytics
6. **Principle of least privilege** - Grant minimal RBAC permissions needed

## Troubleshooting

### Cannot connect to Jump VM via Bastion

1. Check Bastion subnet name is exactly `AzureBastionSubnet`
2. Verify NSG allows Bastion traffic (bastionNsg should be enabled)
3. Ensure Bastion subnet is at least /26 (64 addresses)
4. Check Bastion deployment succeeded in Azure Portal

### Cannot access services from Jump VM

1. Verify private endpoints were created for each service
2. Check private DNS zones are linked to the VNet
3. Ensure NSGs allow traffic from Jump VM subnet to private endpoints subnet
4. Test DNS resolution: `nslookup <service-name>.vault.azure.net`

### Cannot sign in to the Jump VM through Bastion

Sign-in uses **Microsoft Entra ID** — there is no username/password to manage. If the
Bastion connection fails or rejects your credentials:

1. Confirm you are signed in to the Azure portal as the **same Entra ID user** that ran
   `azd up` (or another principal that has been granted the **Virtual Machine
   Administrator Login** or **Virtual Machine User Login** role on the VM).
2. On the Bastion connection blade, ensure **Authentication type** is set to
   **Microsoft Entra ID** (not "Password").
3. Verify the **AADLoginForWindows** extension is in a `Succeeded` state on the VM
   (Portal → VM → Extensions + applications).
4. To grant additional users access, assign one of these roles on the jump VM (or its
   resource group):
   - **Virtual Machine Administrator Login** — sign in as a local administrator
   - **Virtual Machine User Login** — sign in as a standard user

   ```pwsh
   az role assignment create \
     --assignee <user-or-group-object-id> \
     --role "Virtual Machine Administrator Login" \
     --scope <vm-resource-id>
   ```

See [Azure Bastion — Microsoft Entra ID authentication](https://learn.microsoft.com/azure/bastion/bastion-entra-id-authentication)
for full details.

## Related Documentation

- [Azure Bastion Documentation](https://learn.microsoft.com/azure/bastion/)
- [Private Endpoints Documentation](https://learn.microsoft.com/azure/private-link/private-endpoint-overview)
- [Network Security Best Practices](https://learn.microsoft.com/azure/security/fundamentals/network-best-practices)
