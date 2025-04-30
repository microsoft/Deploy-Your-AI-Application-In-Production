## Transfer your existing project connections
This new feature will allow you to keep existing connections and transfer them to the new isolated project. 
During the initial deployment, the user will now be prompted for additional information in the form of boolean 'feature flags'.
![Feature Flags to select what to copy](../img/provisioning/parameterselection.png)

The solution will run a script to find these related connections in your existing subscription, resource group and project. The system will look in the current subscription, resource group and project, unless values are provided for resources in other subscriptions, resource groups or projects. To find these, follow these steps:
- **TENANT_ID** - [how to find](https://learn.microsoft.com/en-us/azure/active-directory/fundamentals/active-directory-how-to-find-tenant#find-tenant-id-through-the-azure-portal)
- **SUBSCRIPTION_ID** - [how to find](https://learn.microsoft.com/en-us/azure/azure-portal/get-subscription-tenant-id#find-your-azure-subscription) 