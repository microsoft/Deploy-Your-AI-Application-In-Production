## Feature Flags

Within this deployment of AI Foundry, we also have coupled several additional Azure services that are commonly deployed when creating an AI solution. We have added the ability to deploy these services at the same time as Foundry, or as an additional run of the deployment to add the services later. 
To allow for this, we leverage several true/false values to either enable or disable (default behavior) the deployment and configuration of the service(s).

Below is a table of the available feature flags in this repository:

| **Feature Flag Name**       | **Effect When Enabled**                                   | **Instructions to Enable**                                                                 |
|------------------------------|---------------------------------------------------------|-------------------------------------------------------------------------------------------|
| `cosmosDbEnabled`           | Enables Cosmos DB integration.                          | Set the environment variable `AZURE_COSMOS_DB_ENABLED` to `true`.                        |
| `sqlServerEnabled`          | Enables SQL Server integration.                         | Set the environment variable `AZURE_SQL_SERVER_ENABLED` to `true`.                       |
| `acrEnabled`                | Enables Azure Container Registry (ACR) integration.     | Set the environment variable `AZURE_ACR_ENABLED` to `true`.                              |
| `apiManagementEnabled`      | Enables API Management integration.                     | Set the environment variable `AZURE_API_MANAGEMENT_ENABLED` to `true`.                   |

To enable these features during the deplpoyment of your Foundry services, simply set the default value of false to 'true'. This will the add that selected feature into the deployment and the features will integrate to the virtual network, private endpoints, and dns zones. 
Additionally, within the infra/ folder you can modify the main.parameters.json file to set the value to 'true' if you plan to deploy with that feature enabled each time. 
