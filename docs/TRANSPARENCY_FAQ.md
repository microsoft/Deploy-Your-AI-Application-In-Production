# Responsible AI Transparency FAQ

## Deploy Your AI Application In Production: Responsible AI FAQ

### What is the Deploy Your AI Application In Production solution accelerator?

This solution accelerator automates the deployment of a complete, production-ready AI application environment in Azure. It provisions Azure AI Foundry, Microsoft Fabric, Azure AI Search, and Microsoft Purview—all pre-wired with private networking, managed identities, and governance controls.

### What is the intended use of this solution accelerator?

This repository is intended to be used as a solution accelerator following the open-source license terms listed in the GitHub repository. The intended purpose is to demonstrate how organizations can:

- Deploy production-grade AI infrastructure with security controls enabled by default
- Integrate data platforms (Fabric) with AI services (Foundry) for retrieval-augmented generation scenarios
- Implement governance and compliance monitoring through Purview integration

The deployed infrastructure is designed to host AI chat applications that use your organization's documents for grounded responses.

### How was this solution accelerator evaluated?

The solution was evaluated for:

- **Infrastructure Security**: Private endpoints, managed identities, and RBAC configurations were validated against Microsoft's Well-Architected Framework
- **Deployment Reliability**: Automated testing in multiple Azure regions to ensure consistent provisioning
- **Integration Correctness**: Validation that Fabric, Search, Foundry, and Purview components are properly connected

### What are the limitations of this solution accelerator?

- **Infrastructure Only**: This accelerator deploys infrastructure and basic integrations. You must still provide your own documents, configure AI prompts, and build the end-user application.
- **Region Availability**: Not all Azure regions support all required services. EastUS2 is recommended.
- **Quota Requirements**: Azure OpenAI and other services have quota limits that may restrict deployment.
- **Network Restrictions**: Some Fabric-to-Search private link scenarios are not yet fully supported by Azure.
- **English Only**: Documentation and sample configurations are provided in English only.

### What operational factors allow for effective and responsible use?

Users can customize several parameters to align the deployment with their organizational requirements:

- **Network Isolation Mode**: Configure the level of network isolation (private endpoints, public access)
- **Model Selection**: Choose which Azure OpenAI models to deploy
- **Capacity Settings**: Adjust Fabric capacity SKU and AI service quotas
- **Governance Configuration**: Connect to existing Purview accounts for compliance monitoring

Please note that these parameters are provided as guidance to start the configuration. Users should adjust the system to meet their specific security, compliance, and operational requirements.

### How can users minimize limitations?

1. **Check Quota Before Deployment**: Use the [quota check guide](./docs/quota_check.md) to ensure sufficient capacity
2. **Review Post-Deployment Steps**: Validate all components are properly configured after deployment
3. **Customize Prompts**: Modify system prompts and configurations for your specific use case
4. **Human Review**: Implement human-in-the-loop validation for AI-generated content in production scenarios

### Data Handling

- This accelerator does not include sample data or documents
- Documents you upload to Fabric lakehouses are stored in your Azure subscription
- Data is indexed by Azure AI Search within your subscription
- No data is sent to Microsoft beyond standard Azure service telemetry

### AI Model Usage

This accelerator deploys Azure OpenAI models (GPT-4o by default) within your Azure subscription. All AI model usage:

- Is subject to [Azure OpenAI Service terms](https://learn.microsoft.com/en-us/legal/cognitive-services/openai/data-privacy)
- Is metered and billed to your Azure subscription
- Follows your organization's Azure OpenAI content filtering policies

### Additional Resources

- [Azure AI Responsible AI Overview](https://learn.microsoft.com/en-us/azure/ai-services/responsible-use-of-ai-overview)
- [Azure OpenAI Transparency Note](https://learn.microsoft.com/en-us/legal/cognitive-services/openai/transparency-note)
- [Microsoft Responsible AI Principles](https://www.microsoft.com/en-us/ai/responsible-ai)
