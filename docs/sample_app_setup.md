# Setup Sample Application

> **Note:** Before proceeding, ensure you have completed the deployment steps described in the project `README.md`.

## Post-Deployment Steps

1. **Access AI Foundry**
    - Connect to your VM jump box using Azure Bastion.
    - Once connected, open AI Foundry.

2. **Create a Data Source**
    - In AI Foundry, create a new Data Source.
    - Upload your data files to this Data Source.

3. **Create an Index**
    - In AI Foundry, create a new Index.
    - Select the Data Source you just created.
    - Choose the existing Azure Cognitive Search service and the deployed text embedding model.

4. **Update App Service Environment Variable**
    - After indexing completes, note the name of your new Index.
    - Update the relevant environment variable in your Azure App Service configuration with this Index name.

5. **Launch and Use the Application**
    - Start your Azure App Service.
    - Open the application and begin chatting with your data.

