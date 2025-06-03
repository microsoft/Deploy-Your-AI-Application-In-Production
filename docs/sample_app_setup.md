# Setup Sample Application

This solution includes an optional sample AI chat application that can be instantiaed along with the other resources to showcase a production-ready, end-to-end application running securly on Azure. Application image is pulled from a public registry and the [source code can be found here](https://github.com/microsoft/sample-app-aoai-chatGPT).

## Pre-Deployment Steps

### Setup Entra App Registration

The sample application requires an [application registration in Microsoft Entra](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app). This is used for authentication. The deployment process will automatically create the application registration by default or an existing applicaiton registration can be used.

#### Create Application Registration Automatically

Following the steps below and executing a deployment will automatically create the Application Registration in Microsoft Entra and set the required environment variables. The application registration will then be used for that AZD environment when deploying. The executing user will need sufficient permissions on the tenant to create registrations (like the [Application Developer role](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference#application-developer)).

#### Use Existing Application Registration

In the Azure Portal, either [create a new registration](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app) or navigate to an existing registration.

* Note the *Application (client) ID* and *Object ID* displayed on the overview page.
* Navigate to "Certificates & secrets" > "New client secret".
* Enter a description and expiration, then click "Add".
* Copy and securely store the generated client secret value, as it will not be shown again.

The client ID and client secret are required for authenticating your application with Microsoft Entra.

Set the following environment variables after establishing an AZD environment:

```sh
azd env set 'AZURE_AUTH_APP_ID' '<your-object-id>'
azd env set 'AZURE_AUTH_CLIENT_ID' '<your-client-id>'
azd env set 'AZURE_AUTH_CLIENT_SECRET' '<your-client-secret>'
```

## Deployment Steps

### Setup Environment Variables

In order to have the sample application infrastructure deployed, certain parameter requirements must be met. Set specific environment variables listed in the below AZD command block after setting up a new AZD environment and prior to running `azd up` to properly deploy the sample application. 

```sh
azd env set 'AZURE_APP_SAMPLE_ENABLED' 'true'
azd env set 'AZURE_AI_SEARCH_ENABLED' 'true'
azd env set 'AZURE_COSMOS_DB_ENABLED' 'true'
```

### AI Models Parameter Requirements

Also, the `aiModelDeployments` parameter in the [main.parameters.json](/infra/main.parameters.json) must contain two AI model deployments in this specific order (Note: the default values meet these requirements):

1. Text Embedding model (e.g., `text-embedding-ada-002`, `text-embedding-3-small`, `text-embedding-3-large`)
2. Chat Completion model (e.g., `gpt-4`, `gpt-4o`, `gpt-4o-mini`)

### Deploy

Follow the [standard deployment guide](./local_environment_steps.md).

## Post-Deployment Steps

1. **Access AI Foundry**
    - Connect to your VM jump box using Azure Bastion.
    - Once connected, browse to the Azure Portal
    - Select the Azure AI Project resource and load the AI Foundry

2. **Create a Data Source**
    - In AI Foundry, select *Data + Indexes*, and click *+New Data*
    - For Data Source, select to Upload Files/Folders, then Upload Files
    - Give the Data Source a name and click Create    

3. **Create an Index**
    - In AI Foundry, select *Data + Indexes*, and click *+New Index*
    - Select your Data Source
    - Choose the existing Azure Cognitive Search service
    - Keep the suggested Index name or supply a different name
    - In the Search settings, select the *text-embedding-3-model* model deployment.
    - Review and click Create Vector Index. Note this can take a few minutes to complete.

4. **Update App Service Environment Variable**
    - After indexing completes, note the name of your new Index.
    - In the Azure Portal, navigate to the Azure App Service and update the relevant Environment Variable in the Configuration with this Index name.

5. **Launch and Use the Application**
    - Navigate to the Azure App Service in the Azure Portal
    - Browse application and begin chatting with your data.

