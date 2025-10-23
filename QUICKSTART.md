# AI Landing Zone - azd Deployment Quick Start

## 🚀 Deploy in 5 Minutes

This branch provides a streamlined deployment using the Azure AI Landing Zone as a git submodule.

### Prerequisites
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- Active Azure subscription

### Deploy Now

```bash
# 1. Initialize submodule
git submodule update --init --recursive

# 2. Create environment
azd env new <your-env-name>

# 3. Set location
azd env set AZURE_LOCATION eastus2

# 4. Deploy
azd up
```

That's it! The deployment will create:
- ✅ Virtual Network with private networking
- ✅ Azure Bastion + Jump VM (for accessing private resources)
- ✅ AI Foundry Project with GPT-4o and embeddings
- ✅ Azure Cosmos DB
- ✅ Azure AI Search
- ✅ Azure Key Vault
- ✅ Container Registry + Container Apps Environment
- ✅ Log Analytics + Application Insights
- ✅ All configured with private endpoints (no public access)

### Customize Your Deployment

**Edit `infra/main.bicepparam`** (recommended - with IntelliSense!) or `infra/main.parameters.json` to:
- **Change AI models**: Update `aiFoundryDefinition.aiModelDeployments`
- **Enable/disable services**: Toggle flags in `deployToggles`
- **Adjust networking**: Modify `vNetDefinition` subnets and address spaces
- **Add services**: Enable API Management, Application Gateway, Firewall, etc.

💡 **Tip**: The `.bicepparam` file provides type safety and IntelliSense in VS Code!

### Full Documentation

📖 **Complete Guide**: [docs/AZD_DEPLOYMENT.md](docs/AZD_DEPLOYMENT.md)

Includes:
- Detailed parameter reference
- Advanced configuration options
- Using existing resources
- Troubleshooting guide
- Architecture overview

### What's Different in This Branch?

- ✨ **No local Bicep modules** - Everything uses the AI Landing Zone submodule
- ✨ **Minimal wrapper** - `infra/main.bicep` is just 160 lines
- ✨ **azd-native** - Full Azure Developer CLI integration
- ✨ **Type-safe parameters** - Uses AI Landing Zone's type system
- ✨ **No template specs** - Direct Bicep compilation

### Architecture

```
infra/main.bicep (160 lines - thin wrapper)
    ↓
submodules/ai-landing-zone/bicep/infra/main.bicep
    ↓
Full AI Landing Zone deployment (3000+ lines)
```

### Verify Deployment

```bash
# Check all deployed resources
azd env get-values

# View in Azure Portal
az resource list --resource-group rg-<your-env-name> --output table
```

### Clean Up

```bash
azd down --purge
```

### Support

- **AI Landing Zone Issues**: https://github.com/Azure/ai-landing-zone/issues
- **Full Documentation**: [docs/AZD_DEPLOYMENT.md](docs/AZD_DEPLOYMENT.md)
- **Original README**: [README.md](README.md)

---

**Branch**: `feature/azd-submodule-deployment`  
**Status**: ✅ Ready for deployment  
**Last Updated**: October 2025
