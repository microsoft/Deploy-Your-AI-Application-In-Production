<!---------------------[  Description  ]------------------<recommended> section below------------------>

# Deploy your AI Application in Production

## Overview

This solution accelerator provides a foundational template for deploying an AI hub and project into an isolated environment (vNet) within Azure. The deployed features follow Microsoft's Well-Architected Framework (WAF) to establish isolated infrastructure for an AI Foundry project, intended to move from a Proof of Concept state to a production-ready application. 

This template leverages Azure Verified Modules (AVM) and the Azure Developer CLI (AZD) to provision WAF-aligned infrastructure. This infrastructure includes AI Foundry elements, a virtual network (VNET), private endpoints, Key Vault, a storage account, and optional WAF-aligned resources (such as Cosmos DB and SQL Server) that can be leveraged with AI Foundry–developed projects.

The following deployment automates our recommended configuration to protect your data and resources by using Microsoft Entra ID role-based access control, a managed network, and private endpoints. We recommend disabling public network access for Azure OpenAI resources, Azure AI Search resources, and storage accounts. Using selected networks with IP rules isn't supported because the services' IP addresses are dynamic.

AI Foundry has two network isolation aspects, this repository will automate:
1. Configuring the network isolation of the Azure AI Foundry hub and project managed compute (compute instance, serverless compute, managed online endpoint) [Configure Managed Network](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/configure-managed-network)
2. Configuring the virtual network, private end points and private link services to isolate resources to connect to the hub and project in a secure way. [Secure Data Playground](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/secure-data-playground)


## Architecture
The diagram below illustrates the capabilities included in the template.

![Network Isolation Infrastructure](./img/Architecture/Deploy-AI-App-in-Prod-Architecture_final.png)

| Diagram Step      | Description     |
| ------------- | ------------- |
| 1 | Tenant users utilize Microsoft Entra ID and multi-factor authentication to log in to the jumpbox virtual machine |
| 2 | Users and workloads within the client's virtual network can utilize private endpoints to access managed resources and the hub workspace|
| 3 | The workspace-managed virtual network is automatically generated for you when you configure managed network isolation to one of the following modes: <br> Allow Internet Outbound <br> Allow Only Approved Outbound|
| 4 | The online endpoint is secured with Microsoft Entra ID authentication. Client applications must obtain a security token from the Microsoft Entra ID tenant before invoking the prompt flow hosted by the managed deployment and available through the online endpoint|
| 5 | API Management creates consistent, modern API gateways for existing backend services. In this architecture, API Management is used in a fully private mode to offload cross-cutting concerns from the API code and hosts.|




## Key Features
### What solutions does this enable? 
- Deploys AI hub and AI project into a virtual network with all dependent services connected via private end points. 

- Configures AI Foundry, adhering to the best practices outlined in the Well Architected Framework.

- Provides the ability to add additional Azure services during deployment, configured to connect via isolation, to facilitate your AI project 
  
## Prerequisites and high-level steps

1. Have access to an Azure subscription and Entra ID account with Contributor permissions.
2. Confirm the subscription you are deploying into has the [Required Roles and Scopes](Required_roles_scopes_resources.md) and 
3. If deploying from your [local environment](local_environment_steps.md) Install the [Azure Developer CLI (AZD)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd?tabs=winget-windows%2Cbrew-mac%2Cscript-linux&pivots=os-windows)
4. If deploying via [GitHub Codespaces](github_code_spaces_steps.md) - requires the user to be on a GitHub Team or Enterprise Cloud plan
5. If leveraging [One-click deployment](#quick-deploy)
6. If leveraging [GitHub Actions](github_actions_steps.md)

For additional documentation of the default enabled services of this solution accelerator, please see:

1. [Azure Open AI Service](https://learn.microsoft.com/en-us/azure/ai-services/openai/)
2. [Azure AI Search](https://learn.microsoft.com/en-us/azure/search/)
3. [Azure AI hub](https://learn.microsoft.com/en-us/azure/ai-foundry/)
4. [Azure AI project](https://learn.microsoft.com/en-us/azure/ai-foundry/)
5. [Azure Container Registry](https://learn.microsoft.com/en-us/azure/container-registry/)
6. [Azure Virtual Machines](https://learn.microsoft.com/en-us/azure/virtual-machines/)
7. [Azure Storage](https://learn.microsoft.com/en-us/azure/storage/)
8. [Azure Virtual Network](https://learn.microsoft.com/en-us/azure/virtual-network/)
9. [Azure Key vault](https://learn.microsoft.com/en-us/azure/key-vault/)
10. [Azure Bastion](https://learn.microsoft.com/en-us/azure/bastion/)
11. [Azure Log Analytics](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-analytics-overview)
12. [Azure Application Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview)


<h2><img src="./img/Documentation/quickDeploy.png" width="64">
<br/>
QUICK DEPLOY
</h2>

| [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/microsoft/Deploy-Your-AI-Application-In-Production) | [![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https://github.com/microsoft/Deploy-Your-AI-Application-In-Production) | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fmicrosoft%2FDeploy-Your-AI-Application-In-Production%2Fmain%2Finfra%2Fmain.json) |
|---|---|---|
[Steps to deploy with GitHub Codespaces](DeployViaCodeSpaces.md)



## Connect to and validate access to the new environment 
Follow the post deployment steps [Post Deployment Steps](post_deployment_steps.md) to connect to the isolated enviornment.


## Deploy your application in the isolated environment
- Provision additional production resources (data, storage, services) and configure secure access.
- 
- Leverage the Microsoft Learn documentation regarding deploying a web app within AI Foundry[Configure Web App](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/on-your-data-configuration#azure-ai-foundry-portal)


<h2>
Supporting documents
</h2>

### Additional resources

- [Azure AI Foundry documentation](https://learn.microsoft.com/en-us/azure/ai-studio/)
- [Azure Well Architecture Framework documentation](https://learn.microsoft.com/en-us/azure/well-architected/)
- [Azure OpenAI Service - Documentation, quickstarts, API reference - Azure AI services | Microsoft Learn](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/use-your-data)
- [Azure AI Content Understanding documentation](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/)



---

## Disclaimers

To the extent that the Software includes components or code used in or derived from Microsoft products or services, including without limitation Microsoft Azure Services (collectively, “Microsoft Products and Services”), you must also comply with the Product Terms applicable to such Microsoft Products and Services. You acknowledge and agree that the license governing the Software does not grant you a license or other right to use Microsoft Products and Services. Nothing in the license or this ReadMe file will serve to supersede, amend, terminate or modify any terms in the Product Terms for any Microsoft Products and Services. 

You must also comply with all domestic and international export laws and regulations that apply to the Software, which include restrictions on destinations, end users, and end use. For further information on export restrictions, visit https://aka.ms/exporting. 

You acknowledge that the Software and Microsoft Products and Services (1) are not designed, intended or made available as a medical device(s), and (2) are not designed or intended to be a substitute for professional medical advice, diagnosis, treatment, or judgment and should not be used to replace or as a substitute for professional medical advice, diagnosis, treatment, or judgment. Customer is solely responsible for displaying and/or obtaining appropriate consents, warnings, disclaimers, and acknowledgements to end users of Customer’s implementation of the Online Services. 

You acknowledge the Software is not subject to SOC 1 and SOC 2 compliance audits. No Microsoft technology, nor any of its component technologies, including the Software, is intended or made available as a substitute for the professional advice, opinion, or judgement of a certified financial services professional. Do not use the Software to replace, substitute, or provide professional financial advice or judgment.  

BY ACCESSING OR USING THE SOFTWARE, YOU ACKNOWLEDGE THAT THE SOFTWARE IS NOT DESIGNED OR INTENDED TO SUPPORT ANY USE IN WHICH A SERVICE INTERRUPTION, DEFECT, ERROR, OR OTHER FAILURE OF THE SOFTWARE COULD RESULT IN THE DEATH OR SERIOUS BODILY INJURY OF ANY PERSON OR IN PHYSICAL OR ENVIRONMENTAL DAMAGE (COLLECTIVELY, “HIGH-RISK USE”), AND THAT YOU WILL ENSURE THAT, IN THE EVENT OF ANY INTERRUPTION, DEFECT, ERROR, OR OTHER FAILURE OF THE SOFTWARE, THE SAFETY OF PEOPLE, PROPERTY, AND THE ENVIRONMENT ARE NOT REDUCED BELOW A LEVEL THAT IS REASONABLY, APPROPRIATE, AND LEGAL, WHETHER IN GENERAL OR IN A SPECIFIC INDUSTRY. BY ACCESSING THE SOFTWARE, YOU FURTHER ACKNOWLEDGE THAT YOUR HIGH-RISK USE OF THE SOFTWARE IS AT YOUR OWN RISK.  

* Data Collection. The software may collect information about you and your use of the software and send it to Microsoft. Microsoft may use this information to provide services and improve our products and services. You may turn off the telemetry as described in the repository. There are also some features in the software that may enable you and Microsoft to collect data from users of your applications. If you use these features, you must comply with applicable law, including providing appropriate notices to users of your applications together with a copy of Microsoft’s privacy statement. Our privacy statement is located at https://go.microsoft.com/fwlink/?LinkID=824704. You can learn more about data collection and use in the help documentation and our privacy statement. Your use of the software operates as your consent to these practices.
