# Quick Start: Modular Deployment

This guide shows how to deploy the complete AI Landing Zone infrastructure using the modular orchestrator approach.

## Prerequisites

1. **Azure Subscription** with Owner or Contributor access
2. **Azure CLI** installed and authenticated
   ```bash
   az login
   az account set --subscription <subscription-id>
   ```
3. **Azure Developer CLI (azd)** version 1.15.0 or higher
   ```bash
   # Install azd (if not already installed)
   # Windows (PowerShell)
   powershell -ex AllSigned -c "Invoke-RestMethod 'https://aka.ms/install-azd.ps1' | Invoke-Expression"
   
   # Linux/macOS
   curl -fsSL https://aka.ms/install-azd.sh | bash
   ```

## One-Time Setup

### 1. Clone the Repository

```bash
git clone https://github.com/microsoft/Deploy-Your-AI-Application-In-Production.git
cd Deploy-Your-AI-Application-In-Production
```

### 2. Checkout the Modular Deployment Branch

```bash
git checkout feature/staged-deployment
```

### 3. Initialize the AI Landing Zone Submodule

```bash
git submodule update --init --recursive
```

## Deployment

### 1. Initialize Azure Developer CLI

```bash
# Initialize azd (first time only)
azd init

# Or create a new environment if already initialized
azd env new myaiapp
```

### 2. Deploy All Stages

```bash
# Deploy everything - no environment variables required!
azd up
```

**Important Notes:**
- **Jump VM Password** is auto-generated for security (same as original AI Landing Zone)
  - After deployment, reset the password in Azure Portal if you need to access the VM
  - Go to: Azure Portal → Jump VM → Reset password
- **baseName** is automatically derived from your resource group name (no need to set)
- **location** defaults to `eastus2` (change with `azd env set AZURE_LOCATION <region>` if needed)
- **Resource group** is automatically created by azd using the pattern `rg-<env-name>`

### 3. (Optional) Set Custom Jump VM Password

If you want to use a specific password instead of the auto-generated one, you can override it:

```bash
# Uncomment the jumpVmAdminPassword line in infra/main-orchestrator.bicepparam
# Then set the environment variable:
azd env set JUMP_VM_ADMIN_PASSWORD "YourSecureP@ssw0rd123!"

# Re-deploy to apply the custom password
azd up
```

### Deployment Timeline

The `azd up` command will deploy all 5 stages sequentially:
1. **Stage 1**: Deploy networking (VNet, 5 subnets, 5 NSGs) - ~5 min
2. **Stage 2**: Deploy monitoring (Log Analytics, App Insights) - ~2 min  
3. **Stage 3**: Deploy security (Key Vault, Bastion, Jump VM) - ~12 min
4. **Stage 4**: Deploy data services (Storage, Cosmos DB, AI Search, ACR) - ~10 min
5. **Stage 5**: Deploy compute & AI (Container Apps, AI Foundry) - ~15 min

**Total time: ~45-55 minutes**

## What Gets Deployed

### Networking
- ✅ Virtual Network (192.168.0.0/22)
- ✅ 5 Subnets (agent, private endpoint, bastion, jumpbox, container apps)
- ✅ 5 Network Security Groups

### Monitoring
- ✅ Log Analytics Workspace
- ✅ Application Insights

### Security
- ✅ Key Vault (RBAC-enabled)
- ✅ Azure Bastion (Standard SKU)
- ✅ Windows 11 Jump VM

### Data Services
- ✅ Storage Account (private endpoint)
- ✅ Cosmos DB (private endpoint)
- ✅ AI Search (private endpoint)
- ✅ Container Registry Premium (private endpoint)

### Compute & AI
- ✅ Container Apps Environment
- ✅ AI Foundry Project
- ✅ GPT-4o model deployment (20K TPM)
- ✅ text-embedding-3-small deployment (120K TPM)

## Accessing Your Resources

### Via Azure Portal
```bash
# Get resource group name
azd env get-values | grep AZURE_RESOURCE_GROUP

# Open in portal
echo "https://portal.azure.com/#@/resource$(az group show -n <rg-name> --query id -o tsv)"
```

### Via Bastion & Jump VM
All private resources (Storage, Cosmos DB, AI Search, etc.) are accessible through:
1. Navigate to Azure Portal → Jump VM
2. Click "Connect" → "Connect via Bastion"
3. Enter credentials (username: `azureuser`, password: your `JUMP_VM_ADMIN_PASSWORD`)
4. From Jump VM, access private endpoints using private DNS names

## Post-Deployment

### View Deployment Outputs
```bash
azd env get-values
```

Key outputs include:
- `AZURE_CONTAINER_REGISTRY_NAME` - Your ACR name
- `AZURE_COSMOS_DB_NAME` - Your Cosmos DB account
- `AZURE_SEARCH_NAME` - Your AI Search service
- `AZURE_KEY_VAULT_NAME` - Your Key Vault
- `AZURE_AI_PROJECT_NAME` - Your AI Foundry project

### Test AI Foundry
```bash
# Get AI Foundry project details
azd env get-values | grep AI_PROJECT
```

Then open AI Foundry Studio:
1. Navigate to [https://ai.azure.com](https://ai.azure.com)
2. Select your project
3. Test model deployments in the Playground

## Updating the Deployment

To update specific stages:

```bash
# Just re-run azd up
azd up

# Or deploy specific resource group manually
az deployment group create \
  --resource-group <rg-name> \
  --template-file infra/main-orchestrator.bicep \
  --parameters @infra/params/main.bicepparam
```

## Troubleshooting

### Issue: "Password does not meet complexity requirements"
**Solution**: Ensure `JUMP_VM_ADMIN_PASSWORD` has:
- At least 12 characters
- Uppercase and lowercase letters
- At least one number
- At least one special character

### Issue: "Quota exceeded for OpenAI"
**Solution**: Check your Azure OpenAI quota:
```bash
az cognitiveservices account list-usage \
  --name <openai-account> \
  --resource-group <rg-name>
```
Request quota increase if needed at [https://aka.ms/oai/quotaincrease](https://aka.ms/oai/quotaincrease)

### Issue: "Subnet is in use"
**Solution**: Ensure no resources are using the VNet before redeployment. Delete the resource group completely:
```bash
azd down --purge
```

## Clean Up

To delete all resources:

```bash
# Delete everything including the resource group
azd down --purge

# Or just delete the resource group
az group delete --name <rg-name> --yes --no-wait
```

## Advanced: Customization

See [MODULAR_DEPLOYMENT.md](docs/MODULAR_DEPLOYMENT.md) for:
- Customizing individual stages
- Adding new stages
- Modifying AI model deployments
- Changing networking configuration

## Architecture Diagrams

See [docs/](docs/) folder for detailed architecture documentation.

## Support

- **Documentation**: [docs/MODULAR_DEPLOYMENT.md](docs/MODULAR_DEPLOYMENT.md)
- **Issues**: [GitHub Issues](https://github.com/microsoft/Deploy-Your-AI-Application-In-Production/issues)
- **AI Landing Zone**: [GitHub Repo](https://github.com/Azure/ai-landing-zone)
