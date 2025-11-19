# GitHub Actions Pipeline Deployment Steps (CI/CD)

This guide will help you set up automated deployment using GitHub Actions for continuous integration and continuous deployment (CI/CD) of your AI application infrastructure.

## Overview

The GitHub Actions workflow automates the deployment process using the Azure Developer CLI (AZD). When configured, it will automatically provision and deploy your infrastructure to Azure whenever changes are pushed to the main branch, or it can be triggered manually via workflow dispatch.

## Prerequisites

Before setting up GitHub Actions deployment, ensure you have:

1. **Azure Subscription**: An active Azure subscription with appropriate permissions
2. **Repository Access**: Owner or admin access to your GitHub repository (fork or clone of this repository)
3. **Azure CLI**: For initial setup commands (can be run locally or in Codespaces)
4. **Required Roles**: Confirm your subscription has the [Required Roles and Scopes](Required_roles_scopes_resources.md)

## Architecture

The GitHub Actions workflow performs the following:
- Checks out the repository code
- Installs the Azure Developer CLI (AZD)
- Authenticates to Azure using federated credentials (no secrets needed!)
- Provisions infrastructure using `azd provision`

## Setup Steps

### Step 1: Create an Azure Service Principal with Federated Credentials

GitHub Actions uses [OpenID Connect (OIDC)](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect) to authenticate with Azure, which is more secure than using secrets.

1. **Login to Azure CLI** (from your local machine or Codespaces):
   ```bash
   az login
   ```

2. **Set your subscription**:
   ```bash
   az account set --subscription <your-subscription-id>
   ```

3. **Create a resource group** (if you don't have one):
   ```bash
   az group create --name <resource-group-name> --location <location>
   ```

4. **Create a service principal with federated credentials**:
   ```bash
   az ad sp create-for-rbac --name "github-actions-deployment" \
     --role contributor \
     --scopes /subscriptions/<subscription-id>/resourceGroups/<resource-group-name> \
     --sdk-auth
   ```

   Save the output, which includes:
   - `clientId`
   - `tenantId`
   - `subscriptionId`

5. **Create federated credentials for the service principal**:
   ```bash
   az ad app federated-credential create \
     --id <application-object-id> \
     --parameters '{
       "name": "github-actions-deploy",
       "issuer": "https://token.actions.githubusercontent.com",
       "subject": "repo:<your-github-org>/<your-repo-name>:ref:refs/heads/main",
       "audiences": ["api://AzureADTokenExchange"]
     }'
   ```

   Replace `<your-github-org>/<your-repo-name>` with your repository path (e.g., `microsoft/Deploy-Your-AI-Application-In-Production`).

### Step 2: Configure GitHub Repository Variables

GitHub Actions uses repository variables for configuration. Navigate to your repository on GitHub:

1. Go to **Settings** → **Secrets and variables** → **Actions** → **Variables** tab
2. Add the following **repository variables**:

   | Variable Name | Value | Description |
   |--------------|-------|-------------|
   | `AZURE_CLIENT_ID` | Your service principal client ID | From Step 1 output |
   | `AZURE_TENANT_ID` | Your Azure tenant ID | From Step 1 output |
   | `AZURE_SUBSCRIPTION_ID` | Your Azure subscription ID | From Step 1 output |
   | `AZURE_RESOURCE_GROUP` | Your resource group name | Where resources will be deployed |
   | `AZURE_ENV_NAME` | Environment name (≤12 chars) | Unique name for your environment |
   | `AZURE_LOCATION` | Azure region | e.g., `eastus2`, `westus2` |

   ![Image showing GitHub Actions variables configuration](../img/provisioning/github_actions_variables.png)

### Step 3: Configure GitHub Repository Secrets

You'll need to set up the initial environment configuration as a secret:

1. **Create an AZD environment locally** (if you haven't already):
   ```bash
   azd init
   azd env new <environment-name>
   ```

2. **Set required environment variables**:
   ```bash
   azd env set AZURE_LOCATION <location>
   azd env set AZURE_VM_ADMIN_PASSWORD <secure-password>
   # Add other required environment variables as needed
   ```

3. **Export the environment configuration**:
   ```bash
   azd env get-values
   ```

4. **Create a GitHub secret**:
   - Go to **Settings** → **Secrets and variables** → **Actions** → **Secrets** tab
   - Click **New repository secret**
   - Name: `AZD_INITIAL_ENVIRONMENT_CONFIG`
   - Value: Paste the output from `azd env get-values`

### Step 4: Assign Required Azure Roles

Ensure the service principal has the necessary permissions:

```bash
# Assign Contributor role (if not already assigned)
az role assignment create \
  --assignee <client-id> \
  --role Contributor \
  --scope /subscriptions/<subscription-id>/resourceGroups/<resource-group-name>

# Assign User Access Administrator (needed for role assignments during deployment)
az role assignment create \
  --assignee <client-id> \
  --role "User Access Administrator" \
  --scope /subscriptions/<subscription-id>/resourceGroups/<resource-group-name>
```

## Running the Workflow

### Manual Trigger (Workflow Dispatch)

1. Navigate to your repository on GitHub
2. Go to **Actions** tab
3. Select **AZD Deployment** workflow
4. Click **Run workflow**
5. Select the branch (typically `main`)
6. Click **Run workflow**

   ![Image showing manual workflow trigger](../img/provisioning/github_actions_dispatch.png)

### Automatic Trigger (Push to Main)

The workflow automatically runs when code is pushed to the `main` branch:

```bash
git add .
git commit -m "Update infrastructure configuration"
git push origin main
```

## Monitoring Deployment

1. Go to the **Actions** tab in your GitHub repository
2. Click on the running workflow to see real-time logs
3. Expand each step to view detailed output
4. The deployment typically takes 15-20 minutes

   ![Image showing workflow execution](../img/provisioning/github_actions_running.png)

## Post-Deployment Verification

After the workflow completes successfully:

1. **Verify Resources in Azure Portal**:
   - Navigate to your resource group in the [Azure Portal](https://portal.azure.com)
   - Confirm all resources have been provisioned

2. **Connect to the Isolated Environment**:
   Follow the [Post Deployment Steps](post_deployment_steps.md) to verify the secure network configuration and access the environment.

3. **Check Network Isolation**:
   Follow the [Verify Services on Network](Verify_Services_On_Network.md) guide to ensure private endpoints are configured correctly.

## Troubleshooting

### Common Issues

1. **Authentication Failures**:
   - Verify federated credentials are correctly configured
   - Ensure the repository path in the federated credential matches exactly
   - Check that `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` are set correctly

2. **Permission Errors**:
   - Verify the service principal has `Contributor` and `User Access Administrator` roles
   - Check that the scope includes the correct resource group

3. **Quota Issues**:
   - Follow the [Quota Check Instructions](quota_check.md) before deployment
   - The workflow includes automated quota validation

4. **Timeout Errors**:
   - Consider deploying to a different Azure region
   - Check [region availability](https://learn.microsoft.com/azure/ai-services/openai/concepts/models#standard-deployment-model-availability)

### Viewing Detailed Logs

To get more detailed information:
1. Click on the failed workflow run
2. Expand the failed step
3. Review error messages and stack traces
4. Check Azure Activity Log in the portal for deployment details

## Updating Configuration

To update deployment parameters:

1. **Update repository variables** in GitHub Settings
2. **Update the secret** `AZD_INITIAL_ENVIRONMENT_CONFIG` if environment-specific values change
3. **Re-run the workflow** manually or push to main

## Security Best Practices

- ✅ **Use OIDC authentication** (federated credentials) instead of storing secrets
- ✅ **Limit service principal permissions** to only required resource groups
- ✅ **Use separate environments** for development, staging, and production
- ✅ **Enable branch protection rules** on the main branch
- ✅ **Review workflow logs** regularly for security issues
- ✅ **Rotate credentials periodically** following your organization's policies

## Additional Resources

- [Azure Developer CLI Documentation](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/)
- [GitHub Actions for Azure](https://github.com/Azure/actions)
- [Configuring OpenID Connect in Azure](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [Azure AI Foundry Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)

## Next Steps

After successful deployment:
- [Add additional Azure services](add_additional_services.md) to your environment
- [Deploy a sample application](sample_app_setup.md) to test your infrastructure
- [Transfer an existing Azure AI Project](transfer_project_connections.md) if migrating
- [Modify deployed models](modify_deployed_models.md) as needed

## Contributing

This project welcomes contributions and suggestions. Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
