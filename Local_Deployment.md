# Local Deployment

## Overview

This solution accelerator providates a foundation template for deploying a Project within AI Foundry into a secure, private, and protected landing zone within Azure. This zone will be established under Microsoft's Well-Architected Framework (WAF) to provide secure infrastructure for an AI Foundry Project intended to move from a Proof of Concept state to a production-ready application.

This template leverages Azure Verified Modules (AVM) and the Azure Developer CLI (AZD) to provision WAF-aligned infrastructure. This infrastructure includes AI Foundry elements, VNET, Private Endpoints, Key Vault, Storage Account and optional WAF-aligned resources such as Cosmos DB and SQL Server to leverage with AI Foundry developed Projects.

## Prerequisites

- Azure Subscription and Entra ID Account with approprite Contributor permissions.
- Install the [Azure Developer CLI (AZD)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd?tabs=winget-windows%2Cbrew-mac%2Cscript-linux&pivots=os-windows)

## Setup

### Clone Repository

```bash
git clone https://github.com/microsoft/Deploy-Your-AI-Application-In-Production.git
cd Deploy-Your-AI-Application-In-Production
```

### Establish AZD Environment

This solution uses the [Azure Developer CLI](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/overview) to quickly provision and deploy infrastructure and applications to Azure.

To get started, authenticate with an Azure Subscription ([details](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/reference#azd-auth-login)):

```powershell
azd auth login
```

Establish new environment. Provide a name that represents the application domain:

```powershell
azd env new '<app name>'
```

Optionally establish environment variables via the following commands:

```powershell
azd env set 'AZURE_VM_ADMIN_PASSWORD' '<secure password>'
```

# Deploy

To provision the necessary Azure resoruces and deploy the application, run the UP command:

```powershell
azd up
```

This will kick off and interactive console to provide required flags and parameters to deploy the infrastructure. This deployment will initialize a secure, WAF-aligned AI Foundry environment.

Also, note the `.env` file created at `/.azure/<app name>`. These are the environment configuration output from running the `azd up` command. These values are names of resources created as part of the baseline infrastructure.