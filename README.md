# Deploy Your AI Application In Production

Stand up a complete, production-ready AI application environment in Azure with a single command. This solution accelerator provisions Azure AI Foundry, Microsoft Fabric, Azure AI Search, and connects to your tenant level Microsoft Purview (when resourceId is provided) —all pre-wired with private networking, managed identities, and governance controls—so you can move from proof-of-concept to production in hours instead of weeks.

<br/>

<div align="center">
  
[**SOLUTION OVERVIEW**](#solution-overview) \| [**QUICK DEPLOY**](#quick-deploy) \| [**BUSINESS SCENARIO**](#business-scenario) \| [**SUPPORTING DOCUMENTATION**](#supporting-documentation)

</div>


<!------------------------------------------>
<!-- SOLUTION OVERVIEW                       -->
<!------------------------------------------>
<h2><img src="./docs/images/readme/solution-overview.png" width="48" />
Solution Overview
</h2>

This accelerator extends the [AI Landing Zone](https://github.com/Azure/ai-landing-zone) reference architecture to deliver an enterprise-scale, production-ready foundation for deploying secure AI applications and agents in Azure. It packages Microsoft's Well-Architected Framework principles around networking, identity, and operations from day zero.

### Solution Architecture

| ![Architecture](./img/Architecture/AI-Landing-Zone-without-platform.png) |
|---|

### Key Components

| Component | Purpose |
|-----------|---------|
| **Azure AI Foundry** | Unified platform for AI development, testing, and deployment with playground, prompt flow, and publishing |
| **Microsoft Fabric** | Data foundation with lakehouses (bronze/silver/gold) for document storage and OneLake indexing |
| **Azure AI Search** | Retrieval backbone enabling RAG (Retrieval-Augmented Generation) chat experiences |
| **Microsoft Purview** | Governance layer for cataloging, scans, and Data Security Posture Management |
| **Private Networking** | All traffic secured via private endpoints—no public internet exposure |

<br/>

### Additional Resources

- [AI Landing Zone Documentation](https://github.com/Azure/ai-landing-zone)
- [Azure AI Foundry Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)
- [Microsoft Fabric Documentation](https://learn.microsoft.com/en-us/fabric/)

<br/>

<!-------------------------------------------->
<!-- KEY FEATURES                            -->
<!-------------------------------------------->
### Key features
<details open>
  <summary>Click to learn more about the key features this solution enables</summary>

  - **Single-command deployment** <br/>
  Run `azd up` to provision 30+ Azure resources in ~45 minutes with pre-wired security controls.
  
  - **Production-grade security from day zero** <br/>
  Private endpoints, managed identities, and RBAC enabled by default—no public internet exposure.

  - **Integrated data-to-AI pipeline** <br/>
  Connect Fabric lakehouses → OneLake indexer → AI Search → Foundry playground for grounded chat experiences.

  - **Governance built-in** <br/>
  Microsoft Purview integration for cataloging, scoped scans, and Data Security Posture Management (DSPM).

  - **Extensible AVM-driven platform** <br/>
  Toggle additional Azure services through AI Landing Zone parameters for broader intelligent app scenarios.

</details>

<br /><br />
<!-------------------------------------------->
<!-- QUICK DEPLOY                            -->
<!-------------------------------------------->
<h2><img src="./docs/images/readme/quick-deploy.png" width="48" />
Quick deploy
</h2>

### How to install or deploy

Follow the deployment guide to deploy this solution to your own Azure subscription.

> **Note:** This solution accelerator requires **Azure Developer CLI (azd) version 1.15.0 or higher**. [Download azd here](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd).

[**📘 Click here to launch the Deployment Guide**](./docs/DeploymentGuide.md)

<br/>

| [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/microsoft/Deploy-Your-AI-Application-In-Production) | [![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https://github.com/microsoft/Deploy-Your-AI-Application-In-Production) |
|---|---|

<br/>

>  **Important: This repository uses git submodules**
> <br/>Clone with submodules included:
> ```bash
> git clone --recurse-submodules https://github.com/microsoft/Deploy-Your-AI-Application-In-Production.git
> ```
> If you already cloned without submodules, run:
> ```bash
> git submodule update --init --recursive
> ```
> **GitHub Codespaces and Dev Containers handle this automatically.**

>  **Windows shell note**
> <br/>Preprovision uses `shell: sh`. Run `azd` from Git Bash/WSL so `bash` is available, or switch the `preprovision` hook in `azure.yaml` to the provided PowerShell script if you want to stay in PowerShell.

<br/>

>  **Important: Keep environment-specific values local**
> <br/>This repo reads some settings from your local `azd` environment to avoid committing tenant/subscription-specific values.
> ```bash
> # Stored locally under .azure/ (gitignored)
> azd env set FABRIC_CAPACITY_ADMINS '["you@contoso.com"]'
> azd env set AISEARCH_ADDITIONAL_ACCESS_OBJECT_IDS '["<entraObjectId1>","<entraObjectId2>"]'
> azd env set PURVIEW_ACCOUNT_RESOURCE_ID '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Purview/accounts/<name>'
> ```

<br/>

>  **Important: Check Azure OpenAI Quota Availability**
> <br/>To ensure sufficient quota is available in your subscription, please follow the [quota check instructions guide](./docs/quota_check.md) before deploying.

<br/>

### Prerequisites & Costs

<details open>
  <summary><b>Click to see prerequisites</b></summary>

  | Requirement | Details |
  |-------------|---------|
  | **Azure Subscription** | Owner or Contributor + User Access Administrator permissions |
  | **Microsoft Fabric** | Access to create capacity, workspace (or existing Fabric capacity ID) |
  | **Microsoft Purview** | Existing tenant-level Purview account (or ability to create one) |
  | **Azure CLI** | Version 2.61.0 or later |
  | **Azure Developer CLI** | Version 1.15.0 or later |
  | **Quota** | Sufficient Azure OpenAI quota ([check here](./docs/quota_check.md)) |

</details>

<details>
  <summary><b>Click to see estimated costs</b></summary>

  | Service | SKU | Estimated Monthly Cost |
  |---------|-----|------------------------|
  | Azure AI Foundry | Standard | [Pricing](https://azure.microsoft.com/pricing/details/machine-learning/) |
  | Azure OpenAI | Pay-per-token | [Pricing](https://azure.microsoft.com/pricing/details/cognitive-services/openai-service/) |
  | Azure AI Search | Standard | [Pricing](https://azure.microsoft.com/pricing/details/search/) |
  | Microsoft Fabric | F8 Capacity | [Pricing](https://azure.microsoft.com/pricing/details/microsoft-fabric/) |
  | Virtual Network + Bastion | Standard | [Pricing](https://azure.microsoft.com/pricing/details/azure-bastion/) |

  >  **Cost Optimization:** Fabric capacity can be paused when not in use. Use `az fabric capacity suspend` to stop billing.

  Use the [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) for detailed estimates.

</details>

<br/>

<!------------------------------------------>
<!-- BUSINESS SCENARIO                       -->
<!------------------------------------------>
<h2><img src="./docs/images/readme/business-scenario.png" width="48" />
Business Scenario
</h2>

### What You Get

After deployment, you'll have a complete, enterprise-ready platform that unifies AI development, data management, and governance:

| Layer | What's Deployed | Why It Matters |
|-------|-----------------|----------------|
| **AI Platform** | Azure AI Foundry with OpenAI models, playground, and prompt flow | Build, test, and publish AI chat applications without managing infrastructure |
| **Data Foundation** | Microsoft Fabric with bronze/silver/gold lakehouses and OneLake indexing | Store documents at scale and automatically feed them into your AI workflows |
| **Search & Retrieval** | Azure AI Search with vector and semantic search | Enable RAG (Retrieval-Augmented Generation) for grounded, accurate AI responses |
| **Governance** | Microsoft Purview with cataloging, scans, and DSPM | Track data lineage, enforce policies, and maintain compliance visibility |
| **Security** | Private endpoints, managed identities, RBAC, network isolation | Zero public internet exposure—all traffic stays on the Microsoft backbone |

> 💡 **Note:** When Microsoft Fabric automation supports private link provisioning, the entire solution will operate with full network isolation end-to-end.

<br/>

### Key Features

<details open>
  <summary><b>Click to learn more about key features</b></summary>

  - **Production-grade AI Foundry deployments**
    <br/>Stand up Azure AI Foundry projects in a locked-down virtual network with private endpoints, managed identities, and telemetry aligned to the Well-Architected Framework.

  - **Fabric-powered retrieval workflows**
    <br/>Land documents in a Fabric lakehouse, index them with OneLake + Azure AI Search, and wire the index into the Foundry playground for grounded chat experiences.

  - **Governed data and agent operations**
    <br/>Integrate Microsoft Purview for cataloging, scoped scans, and Data Security Posture Management (DSPM) so compliance teams can monitor the same assets the app consumes.

  - **Extensible AVM-driven platform**
    <br/>Toggle additional Azure services (API Management, Cosmos DB, SQL, and more) through AI Landing Zone parameters to tailor the environment for broader intelligent app scenarios.

  - **Launch-ready demos and pilots**
    <br/>Publish experiences from Azure AI Foundry directly to a browser-based application, giving stakeholders an end-to-end view from infrastructure to user-facing app.

</details>

<br/>

### Sample Workflow

1. **Deploy infrastructure** → Run `azd up` to provision all resources (~45 minutes)
2. **Upload documents** → Add PDFs to the Fabric bronze lakehouse
3. **Index content** → OneLake indexer automatically populates AI Search
4. **Test in playground** → Connect Foundry to the search index and chat with your data
5. **Publish application** → Deploy the chat experience to end users
6. **Monitor governance** → Review data lineage and security posture in Purview

<br/>

<!------------------------------------------>
<!-- SUPPORTING DOCUMENTATION                -->
<!------------------------------------------>
<h2><img src="./docs/images/readme/supporting-documentation.png" width="48" />
Supporting documentation
</h2>

### Deployment & Configuration

| Document | Description |
|----------|-------------|
| [Deployment Guide](./docs/DeploymentGuide.md) | Complete deployment instructions |
| [Post Deployment Steps](./docs/post_deployment_steps.md) | Verify your deployment |
| [Parameter Guide](./docs/PARAMETER_GUIDE.md) | Configure deployment parameters |
| [Quota Check Guide](./docs/quota_check.md) | Check Azure OpenAI quota availability |

### Customization & Operations

| Document | Description |
|----------|-------------|
| [Required Roles & Scopes](./docs/Required_roles_scopes_resources.md) | IAM requirements for deployment |
| [Parameter Guide](./docs/PARAMETER_GUIDE.md) | All deployment parameters, toggles & model configs |
| [Deploy App from Foundry](./docs/deploy_app_from_foundry.md) | Publish playground to App Service |
| [Accessing Private Resources](./docs/ACCESSING_PRIVATE_RESOURCES.md) | Connect via Jump VM |

### Security Guidelines

<details>
  <summary><b>Click to see security best practices</b></summary>

  This template leverages [Managed Identity](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview) between services to eliminate credential management.

  **Recommendations:**
  - Enable [GitHub secret scanning](https://docs.github.com/code-security/secret-scanning/about-secret-scanning) on your repository
  - Consider enabling [Microsoft Defender for Cloud](https://learn.microsoft.com/azure/defender-for-cloud/)
  - Review the [AI Foundry security documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/)

  > ⚠️ **Important:** This template is built to showcase Azure services. Implement additional security measures before production use.

</details>

<br/>

<!-------------------------------------------->
<!-- FEEDBACK & FAQ                          -->
<!-------------------------------------------->
## Provide Feedback

Have questions, found a bug, or want to request a feature? [Submit a new issue](https://github.com/microsoft/Deploy-Your-AI-Application-In-Production/issues) and we'll connect.

<br/>

## Responsible AI Transparency FAQ

Please refer to [Transparency FAQ](./docs/TRANSPARENCY_FAQ.md) for responsible AI transparency details of this solution accelerator.

<br/>

<!-------------------------------------------->
<!-- DISCLAIMERS                             -->
<!-------------------------------------------->
## Disclaimers

<details>
  <summary><b>Click to see full disclaimers</b></summary>

To the extent that the Software includes components or code used in or derived from Microsoft products or services, including without limitation Microsoft Azure Services (collectively, "Microsoft Products and Services"), you must also comply with the Product Terms applicable to such Microsoft Products and Services. You acknowledge and agree that the license governing the Software does not grant you a license or other right to use Microsoft Products and Services. Nothing in the license or this ReadMe file will serve to supersede, amend, terminate or modify any terms in the Product Terms for any Microsoft Products and Services.

You must also comply with all domestic and international export laws and regulations that apply to the Software, which include restrictions on destinations, end users, and end use. For further information on export restrictions, visit https://aka.ms/exporting.

You acknowledge that the Software and Microsoft Products and Services (1) are not designed, intended or made available as a medical device(s), and (2) are not designed or intended to be a substitute for professional medical advice, diagnosis, treatment, or judgment and should not be used to replace or as a substitute for professional medical advice, diagnosis, treatment, or judgment. Customer is solely responsible for displaying and/or obtaining appropriate consents, warnings, disclaimers, and acknowledgements to end users of Customer's implementation of the Online Services.

You acknowledge the Software is not subject to SOC 1 and SOC 2 compliance audits. No Microsoft technology, nor any of its component technologies, including the Software, is intended or made available as a substitute for the professional advice, opinion, or judgement of a certified financial services professional. Do not use the Software to replace, substitute, or provide professional financial advice or judgment.

BY ACCESSING OR USING THE SOFTWARE, YOU ACKNOWLEDGE THAT THE SOFTWARE IS NOT DESIGNED OR INTENDED TO SUPPORT ANY USE IN WHICH A SERVICE INTERRUPTION, DEFECT, ERROR, OR OTHER FAILURE OF THE SOFTWARE COULD RESULT IN THE DEATH OR SERIOUS BODILY INJURY OF ANY PERSON OR IN PHYSICAL OR ENVIRONMENTAL DAMAGE (COLLECTIVELY, "HIGH-RISK USE"), AND THAT YOU WILL ENSURE THAT, IN THE EVENT OF ANY INTERRUPTION, DEFECT, ERROR, OR OTHER FAILURE OF THE SOFTWARE, THE SAFETY OF PEOPLE, PROPERTY, AND THE ENVIRONMENT ARE NOT REDUCED BELOW A LEVEL THAT IS REASONABLY, APPROPRIATE, AND LEGAL, WHETHER IN GENERAL OR IN A SPECIFIC INDUSTRY. BY ACCESSING THE SOFTWARE, YOU FURTHER ACKNOWLEDGE THAT YOUR HIGH-RISK USE OF THE SOFTWARE IS AT YOUR OWN RISK.

</details>
