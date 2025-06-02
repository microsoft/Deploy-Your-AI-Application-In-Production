# Setup Sample Application

This solution includes an optional sample AI chat application that can be instantiaed along with the other resources to showcase a production-ready, end-to-end application running securly on Azure. Application image is pulled from a public registry and the [source code can be found here](https://github.com/microsoft/sample-app-aoai-chatGPT).

## Pre-Deployment Steps

### Setup Entra App Registration

Creates an application registration in Microsoft Entra (formerly Azure Active Directory).

* Navigate to the Microsoft Entra admin center.
* Go to "App registrations" and select "New registration".
* Enter the application details (name, supported account types, redirect URI if needed).
* After registration, note the "Application (client) ID" displayed on the overview page.
* To generate a client secret, go to "Certificates & secrets" > "New client secret".
* Enter a description and expiration, then click "Add".
* Copy and securely store the generated client secret value, as it will not be shown again.

The client ID and client secret are required for authenticating your application with Microsoft Entra.

## Deployment Steps

In order to have the sample application infrastructure deployed, certain parameter requirements must be met. Set specific environment variables listed in the below AZD command block prior to running `azd up` to properly deploy the sample application. 

```sh
azd env set 'AZURE_APP_SAMPLE_ENABLED' true
azd env set AZURE_AI_SEARCH_ENABLED true
azd env set AZURE_COSMOS_DB_ENABLED true
azd env set AZURE_AUTH_APP_ID <your-app-id>
azd env set AZURE_AUTH_CLIENT_ID <your-client-id>
azd env set AZURE_AUTH_CLIENT_SECRET <your-client-secret>
```

Replace `<your-app-id>`, `<your-client-id>`, and `<your-client-secret>` with your actual Azure credentials.

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
    - Start your Azure App Service.
    - Open the application and begin chatting with your data.

