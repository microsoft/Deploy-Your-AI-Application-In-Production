<!---------------------[  Description  ]------------------<recommended> section below------------------>

# Deploy your AI Application in Production

## Overview

<span style="font-size: 3em;">🚀</span> **New: Updated deployment to match Foundry release at Ignite 2025!**
This new update has been tested in the EastUS2 region successfully.

### Deployment Approach

The solution now provisions through the **AI Landing Zone template-spec orchestrator**. During `azd up`, the deployment pipeline dynamically generates the required template specs, publishes them into your subscription for the duration of the run, and then references those specs to deploy each stage. This preserves the modular layout while relying on the hardened template-spec artifacts maintained by the AI Landing Zone team.

Key characteristics:
- Template specs are dynamically created (and cleaned up) for you at deployment time
- Modular stages remain easy to customize through the accompanying Bicep parameter files
- Single-command deployment with `azd up`

---

This accelerator packages the full AI Landing Zone baseline so you can stand up Azure AI Foundry (AIServices) projects inside a governed, virtual network–isolated environment without hand-stitching resources. It moves teams beyond proof-of-concept builds by enforcing Microsoft’s Well-Architected Framework principles around networking, identity, and operations from the very first deployment.

Everything is delivered through Azure Verified Modules (AVM) orchestrated by the Azure Developer CLI, which means repeatable, supportable infrastructure-as-code. Core components—Key Vault, virtual networks, private endpoints, storage, AI Search, Cosmos DB, SQL, and more—ship pre-integrated with Entra ID role-based access control and telemetry. By default the environment runs with public network access disabled for AI OpenAI, AI Search, and storage endpoints, relying on private connectivity and managed identities so production security controls are in place By default, the environment runs with public network access disabled for AI OpenAI, AI Search, and storage endpoints, relying on private connectivity and managed identities so production security controls are in place from day zero.

This repository will automate:
1. Configuring the virtual network, private end points and private link services to isolate resources connecting to the account and project in a secure way. [Secure Data Playground](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/secure-data-playground)
2. Deploying and configuring the network isolation of the Azure AI Foundry control plane and projects (model catalog, playground, prompt flow) within the virtual network, with all supporting services configured behind private endpoints. 
3. Standing up a Microsoft Fabric workspace (capacity, domain, lakehouses) to serve as the data platform for OneLake ingestion and indexing workflows.
4. Integrating with an existing Microsoft Purview tenant-level account to register the Fabric workspace and trigger governance scans.

> **Important:** Azure AI Search shared private links targeting Fabric workspaces are not yet supported. The deployment attempts to configure the connection automatically, but when the platform rejects the `workspace` shared private link request the automation falls back to public connectivity for OneLake indexing. Review `docs/fabric-onelake-private-networking.md` for current workaround steps and monitor Azure updates before relying on private-only access.
>
> To pre-authorize human operators (for example, a "Dev team" Entra group) to validate indexes in the AI Foundry playground, set the `aiSearchAdditionalAccessObjectIds` parameter or environment value with the group’s object ID. The post-provision RBAC scripts will grant the same Search roles to those principals alongside the managed identities.



## Architecture
This solution extends the [AI Landing Zone](https://github.com/Azure/ai-landing-zone) reference architecture. The landing zone provides an enterprise-scale, production-ready foundation with implementations (Portal, Bicep, and Terraform) to deploy secure and resilient AI apps and agents in Azure. It is designed as an application landing zone that can pair with or operate independently from a platform landing zone and follows Azure Verified Modules guidance.

![AI Landing Zone with Platform Landing Zone](https://raw.githubusercontent.com/Azure/ai-landing-zone/main/media/AI-Landing-Zone-with-platform.png)

The diagram above (sourced from the AI Landing Zone repository) highlights the recommended configuration alongside a platform landing zone. Review the upstream project for deeper design considerations, alternative architectures, and extensibility options: [AI Landing Zone on GitHub](https://github.com/Azure/ai-landing-zone).

Building on that baseline, this accelerator provisions every available AI Landing Zone parameter set and layers in Microsoft Fabric’s Unified Data Foundation plus Microsoft Purview so you can demonstrate an end-to-end governed data workflow:

- Stand up the standard AI Landing Zone resource inventory, enabling all parameterized capabilities to showcase how the orchestrator can be tailored per environment.
- Provision Fabric capacity, domain, workspace, and lakehouses to host the document corpus used for retrieval augmented generation (RAG) scenarios.
- Onboard Microsoft Purview, registering the Fabric workspace and collections so the same environment is ready for cataloging and governance.
- Upload documents into the Fabric lakehouse, then run the OneLake indexing automation to create an Azure AI Search index sourced from that data.
- Connect Microsoft Foundry to the freshly built search index, validate the chat experience in the playground, and publish the application to a browser-based experience for stakeholders.
- When combined with the [Data & Agent Governance and Security accelerator](https://github.com/Azure/data-ai-governance-accelerator), demonstrate Data Security Posture Management (DSPM) in Purview to protect and govern the deployed app, completing the story from provisioning through secure operations.



## Features

### What solutions does this enable? 

- **Production-grade AI Foundry deployments** – Stand up Azure AI Foundry (AIServices) projects in a locked-down virtual network with private endpoints, managed identities, and telemetry aligned to the Well-Architected Framework.
- **Fabric-powered retrieval workflows** – Land documents in a Fabric lakehouse, index them with OneLake plus Azure AI Search, and wire the index into the Foundry playground for grounded chat experiences.
- **Governed data and agent operations** – Integrate Microsoft Purview for cataloging, scoped scans, and Data Security Posture Management (DSPM) so compliance teams can monitor the same assets the app consumes.
- **Extensible AVM-driven platform** – Toggle additional Azure services (API Management, Cosmos DB, SQL, and more) through AI Landing Zone parameters to tailor the environment for broader intelligent app scenarios.
- **Launch-ready demos and pilots** – Publish experiences from Azure AI Foundry projects directly from the playground to a browser experience, giving stakeholders an end-to-end view from infrastructure to user-facing application.



## Prerequisites and high-level steps

**Prerequisites**
- Azure subscription where you hold Owner or Contributor plus `User Access Administrator` permissions so resource providers, role assignments, and template specs can be created.
- Access to (or authority to create) a Microsoft Fabric capacity, workspace, and the Purview account you plan to integrate. The deployment adds the Purview managed identity to Fabric, so you must be able to grant that access.
- Azure CLI (2.61.0 or later) and Azure Developer CLI (1.15.0 or later) installed locally, or plan to use one of the ready-made environments: [GitHub Codespaces](docs/github_code_spaces_steps.md) or [Dev Containers](docs/Dev_ContainerSteps.md).
- Ability to supply the document corpus that will populate the Fabric lakehouse, along with any additional principal IDs you want to preload into `aiSearchAdditionalAccessObjectIds` for Foundry validation.


**High-level steps**
1. Fork/Clone the repository, run `azd init`, and create a new environment with `azd env new <name> --subscription <id> --location <region>`.
2. Review `infra/main.bicepparam` (or per-env `.env` overrides) to set Fabric SKUs, Purview resource IDs, and optional toggles such as `aiSearchAdditionalAccessObjectIds` for human operators.
3. Authenticate with Azure using `azd auth login` (or `az login` if running automation) and ensure the required role assignments from [Required Roles and Scopes](docs/Required_roles_scopes_resources.md) are satisfied.
4. Execute `azd up` to provision infrastructure and run the post-provision automation that configures Fabric, Purview, OneLake indexing, and Foundry RBAC.
5. Upload sample documents to the Fabric lakehouse, trigger the OneLake indexer (if not already executed), connect the Foundry playground to the generated Azure AI Search index, and optionally publish the chat experience for end users.
6. If demonstrating governance, enable DSPM insights in Purview and review the policy recommendations against the newly deployed Fabric workspace and Foundry resources.

### Check Azure OpenAI Quota Availability  

To ensure sufficient quota is available in your subscription, please follow **[quota check instructions guide](./docs/quota_check.md)** before deploying the solution.

### Key platform services

This deployment composes the following Azure services to deliver the governed Fabric + Foundry experience:

- **Azure AI Foundry** – AI Foundry is a unified platform that streamlines AI development, testing, deployment, and publishing within a central Azure workspace.
- **Azure AI Search** – Retrieval backbone for OneLake indexing, RAG chat orchestration, and Foundry grounding.
- **Azure AI Services (OpenAI)** – Model endpoint powering the chat and prompt flow experiences.
- **Microsoft Fabric (capacity, domain, workspace, lakehouse)** – Unified data foundation hosting the document corpus and triggering OneLake indexing pipelines.
- **Microsoft Purview** – Governance layer cataloging Fabric assets, enforcing scans, and enabling Data Security Posture Management insights.
- **Core landing zone services** – Azure Virtual Network with private endpoints, Azure Bastion jump box, Key Vault, Storage, Container Registry, Cosmos DB, SQL, Log Analytics, and Application Insights delivered through Azure Verified Modules to satisfy networking, identity, and operations requirements.

## Getting Started

<h2><img src="./img/Documentation/quickDeploy.png" width="64">
<br/>
QUICK DEPLOY
</h2>

| [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/microsoft/Deploy-Your-AI-Application-In-Production) | [![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https://github.com/microsoft/Deploy-Your-AI-Application-In-Production) |
|---|---|
[Steps to deploy with GitHub Codespaces](docs/github_code_spaces_steps.md)| [Steps to deploy with Dev Container](docs/Dev_ContainerSteps.md)


## Connect to and validate access to the new environment 
Follow the post deployment steps [Post Deployment Steps](docs/github_code_spaces_steps.md) to connect to the isolated environment.


## Deploy your application in the isolated environment
- Leverage the Microsoft Learn documentation to provision an app service instance within your secure network [Configure Web App](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/on-your-data-configuration#azure-ai-foundry-portal)
- Follow these instructions to [Add your data and chat with it in the AI Foundry playground](https://learn.microsoft.com/en-us/azure/ai-foundry/tutorials/deploy-chat-web-app#add-your-data-and-try-the-chat-model-again)


## Guidance

### Region Availability

By default, this template uses AI models which may not be available in all Azure regions. Please follow [quota check instructions guide](./docs/quota_check.md) before deploying the solution. Additionally, check for [up-to-date region availability](https://learn.microsoft.com/azure/ai-services/openai/concepts/models#standard-deployment-model-availability) and select a region during deployment accordingly.

### Costs

You can estimate the cost of this project's architecture with [Azure's pricing calculator](https://azure.microsoft.com/pricing/calculator/)


### Security Guidelines

This template leverages [Managed Identity](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview) between services to eliminate the need for developers to manage these credentials. Applications can use managed identities to obtain Microsoft Entra tokens without having to manage any credentials.

To ensure continued best practices in your own repository, we recommend that anyone creating solutions based on our templates ensure that the [Github secret scanning](https://docs.github.com/code-security/secret-scanning/about-secret-scanning) setting is enabled.

You may want to consider additional security measures, such as:
- Enabling Microsoft Defender for Cloud to [secure your Azure resources](https://learn.microsoft.com/azure/defender-for-cloud/),
>#### Important Security Notice
>This template, the application code and configuration it contains, has been built to showcase >Microsoft Azure specific services and tools. We strongly advise our customers not to make this code part of their production environments without implementing or enabling additional security features.
>
>For a more comprehensive list of best practices and security recommendations for Intelligent Applications, [visit our official documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/).

## Resources

- [Azure AI Foundry documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
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
