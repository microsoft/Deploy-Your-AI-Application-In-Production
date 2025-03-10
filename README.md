<!---------------------[  Description  ]------------------<recommended> section below------------------>

# Deploy your AI Application in Production

## Overview

This solution accelerator provides a foundation template for deploying a Project within AI Foundry into a secure, private, isolated environment within Azure. The deployed features follow Microsoft's Well-Architected Framework (WAF) to establish isolated infrastructure for an AI Foundry Project, intended to move from a Proof of Concept state to a production-ready application.

This template leverages Azure Verified Modules (AVM) and the Azure Developer CLI (AZD) to provision WAF-aligned infrastructure. This infrastructure includes AI Foundry elements, a virtual network (VNET), private endpoints, Key Vault, a storage account, and optional WAF-aligned resources (such as Cosmos DB and SQL Server) that can be leveraged with AI Foundry–developed projects.

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
- Deploy AI Foundry application into a secure environment 

- Connect the application to essential Azure services while adhering to the best practices outlined in the Well Architected Framework

- Provide the ability to select services to deploy that are relevant to the project  
  
## Prerequisites

1. Azure subscription and Entra ID account with Contributor permissions.
2. Install the [Azure Developer CLI (AZD)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd?tabs=winget-windows%2Cbrew-mac%2Cscript-linux&pivots=os-windows)
3. Validate [Required Roles and Scopes](Required_Roles_and_Scopes.md)
4. (Optional) [GitHub Codespaces deployment](DeployViaCodeSpaces.md) - requires the user to be on a GitHub Team or Enterprise Cloud plan

# Setup

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

  
## Connect to & Check the New Environment 
In [Azure Portal](https://portal.azure.com), follow this Azure Bastion [guide](https://learn.microsoft.com/en-us/azure/bastion/bastion-connect-vm-rdp-windows#rdp) to access the network isolated AI Foundry hub & project. 

## Connect Your Model 
<!-- Add latest guidance in customer friendly language -->
Configure AI model and settings in [AI Foundry Portal](https://ai.azure.com) 


<h2>
Supporting documents
</h2>

### Additional resources

- [Azure AI Foundry documentation](https://learn.microsoft.com/en-us/azure/ai-studio/)
- [Azure Well Architecture Framework documentation](https://learn.microsoft.com/en-us/azure/well-architected/)
- [Microsoft Fabric documentation - Microsoft Fabric | Microsoft Learn](https://learn.microsoft.com/en-us/fabric/)
- [Azure OpenAI Service - Documentation, quickstarts, API reference - Azure AI services | Microsoft Learn](https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/use-your-data)
- [Azure AI Content Understanding documentation](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/)

<!-- </br>
Responsible AI Transparency FAQ 
</h2> 

Please refer to [Transparency FAQ](./TRANSPARENCY_FAQ.md) for responsible AI transparency details of this solution accelerator. -->

<br/>
<br/>
<br/>

---

## Disclaimers

To the extent that the Software includes components or code used in or derived from Microsoft products or services, including without limitation Microsoft Azure Services (collectively, “Microsoft Products and Services”), you must also comply with the Product Terms applicable to such Microsoft Products and Services. You acknowledge and agree that the license governing the Software does not grant you a license or other right to use Microsoft Products and Services. Nothing in the license or this ReadMe file will serve to supersede, amend, terminate or modify any terms in the Product Terms for any Microsoft Products and Services. 

You must also comply with all domestic and international export laws and regulations that apply to the Software, which include restrictions on destinations, end users, and end use. For further information on export restrictions, visit https://aka.ms/exporting. 

You acknowledge that the Software and Microsoft Products and Services (1) are not designed, intended or made available as a medical device(s), and (2) are not designed or intended to be a substitute for professional medical advice, diagnosis, treatment, or judgment and should not be used to replace or as a substitute for professional medical advice, diagnosis, treatment, or judgment. Customer is solely responsible for displaying and/or obtaining appropriate consents, warnings, disclaimers, and acknowledgements to end users of Customer’s implementation of the Online Services. 

You acknowledge the Software is not subject to SOC 1 and SOC 2 compliance audits. No Microsoft technology, nor any of its component technologies, including the Software, is intended or made available as a substitute for the professional advice, opinion, or judgement of a certified financial services professional. Do not use the Software to replace, substitute, or provide professional financial advice or judgment.  

BY ACCESSING OR USING THE SOFTWARE, YOU ACKNOWLEDGE THAT THE SOFTWARE IS NOT DESIGNED OR INTENDED TO SUPPORT ANY USE IN WHICH A SERVICE INTERRUPTION, DEFECT, ERROR, OR OTHER FAILURE OF THE SOFTWARE COULD RESULT IN THE DEATH OR SERIOUS BODILY INJURY OF ANY PERSON OR IN PHYSICAL OR ENVIRONMENTAL DAMAGE (COLLECTIVELY, “HIGH-RISK USE”), AND THAT YOU WILL ENSURE THAT, IN THE EVENT OF ANY INTERRUPTION, DEFECT, ERROR, OR OTHER FAILURE OF THE SOFTWARE, THE SAFETY OF PEOPLE, PROPERTY, AND THE ENVIRONMENT ARE NOT REDUCED BELOW A LEVEL THAT IS REASONABLY, APPROPRIATE, AND LEGAL, WHETHER IN GENERAL OR IN A SPECIFIC INDUSTRY. BY ACCESSING THE SOFTWARE, YOU FURTHER ACKNOWLEDGE THAT YOUR HIGH-RISK USE OF THE SOFTWARE IS AT YOUR OWN RISK.  

* Data Collection. The software may collect information about you and your use of the software and send it to Microsoft. Microsoft may use this information to provide services and improve our products and services. You may turn off the telemetry as described in the repository. There are also some features in the software that may enable you and Microsoft to collect data from users of your applications. If you use these features, you must comply with applicable law, including providing appropriate notices to users of your applications together with a copy of Microsoft’s privacy statement. Our privacy statement is located at https://go.microsoft.com/fwlink/?LinkID=824704. You can learn more about data collection and use in the help documentation and our privacy statement. Your use of the software operates as your consent to these practices.
