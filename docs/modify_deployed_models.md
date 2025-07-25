## Update AI Model Deployments

The AI Models that can be deployed and attached to the Foundry hub can be modified by changing the parameters within the [main.parameters.json](../infra/main.parameters.json) file.

By modifying the parameters `aiEmbeddingModelDeployment` and `aiGPTModelDeployment`  listed in the parameters.json, different embedding and GPT models can be deployed with the solution and ready for use after the deployment. Simply modify the values to your liking in each of the objects.

```powershell
    "aiEmbeddingModelDeployment": {
      "value": {
        "modelName": modelName,
        "version": modelVersion,
        "capacity": capacity
      }
    },
    "aiGPTModelDeployment": {
      "value": {
        "modelName": "gpt-4o",
        "version": "2024-05-13",
        "capacity": 150
      }
    }
```

To find and validate additional model information, the [AI Foundry](https://ai.azure.com/explore/models) model page has the above parameters to refer to, as does the Microsoft Learn page for [Azure OpenAI Service Models](https://learn.microsoft.com/en-us/azure/ai-services/openai_) information.
