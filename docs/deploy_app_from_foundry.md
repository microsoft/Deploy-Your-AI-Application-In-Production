# Deploy an Application from Azure AI Foundry

This guide explains how to deploy a chat application directly from the Azure AI Foundry playground to Azure App Service.

## Overview

Azure AI Foundry provides a built-in capability to publish playground experiences as web applications. This accelerator deploys the required infrastructure (App Service, managed identity, networking) so you can publish directly from the Foundry playground.

## Prerequisites

- Completed deployment of this accelerator (`azd up`)
- Access to the AI Foundry project via the Jump VM
- An AI Search index with your data (created via OneLake indexer or manually)

## Steps to Deploy an App from Foundry Playground

### 1. Access AI Foundry via Jump VM

Since all resources are deployed with private endpoints, you must access AI Foundry through the Jump VM:

1. Go to the [Azure Portal](https://portal.azure.com)
2. Navigate to your resource group
3. Select the **Jump VM** (Windows Virtual Machine)
4. Click **Connect** → **Bastion**
5. Enter the VM credentials (set during deployment)
6. Once connected, open a browser and navigate to [AI Foundry](https://ai.azure.com)

### 2. Configure Your Playground

1. In AI Foundry, select your **Project**
2. Navigate to **Playgrounds** → **Chat playground**
3. Configure your deployment:
   - Select your **GPT model deployment** (e.g., gpt-4o)
   - Add your **AI Search index** as a data source
   - Configure the system prompt for your use case

### 3. Test Your Configuration

1. Test the chat experience in the playground
2. Verify responses are grounded in your indexed data
3. Adjust system prompts and parameters as needed

### 4. Deploy to Web App

1. Click **Deploy** → **Deploy to a web app**
2. Configure deployment options:
   - **Create new** or **Update existing** web app
   - Select your **Subscription** and **Resource group**
   - Choose the **App Service** deployed by this accelerator (if updating)
3. Review authentication settings (Entra ID is recommended)
4. Click **Deploy**

### 5. Access Your Application

After deployment completes:

1. Navigate to the **App Service** in Azure Portal
2. Copy the **Default domain** URL
3. Access your application (authentication may be required)

## Additional Resources

- [Deploy a web app for chat on your data](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/deploy-web-app)
- [Azure AI Foundry documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Customize the web app](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/deploy-web-app#customize-the-web-app)

## Troubleshooting

### App not accessible from internet

If your App Service is deployed with private endpoints, you'll need to access it through the Jump VM or configure Azure Front Door for public access.

### Authentication errors

Ensure the App Service has the correct managed identity permissions to access:
- Azure OpenAI / AI Services
- Azure AI Search
- Azure Storage (if applicable)

### Data not appearing in responses

Verify that:
1. Your AI Search index contains data
2. The playground is configured to use the correct index
3. The deployed app has the same index configuration
