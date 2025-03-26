# Local Environment Setup

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

Establish a new environment. Provide a name that represents the application domain:

```powershell
azd env new '<app name>'
```

Optionally set environment variables via the following commands:

```powershell
azd env set 'AZURE_VM_ADMIN_PASSWORD' '<secure password>'
```

# Deploy

To provision the necessary Azure resources and deploy the application, run the azd up command:
```powershell
azd up
```
This will kick off an interactive console to provide required flags and parameters to deploy the infrastructure of a secure, WAF-aligned AI Foundry environment.

>- This deployment will take 15-20 minutes to provision the resources in your account. If you get an error or timeout with deployment, changing the location can help, as there may be availability constraints for the resources.
>- Note the `.env` file created at `/.azure/<app name>`. These are the environment configuration output from running the `azd up` command. These values are names of resources created as part of the baseline infrastructure.