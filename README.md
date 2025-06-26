<!---------------------[  Description  ]------------------<recommended> section below------------------>

# Deploy your AI Application in Production

## Overview

<span style="font-size: 3em;">🚀</span> **New: Updated deployment to match Foundry release at Build 2025!**
This new update has been tested in the EastUS2 region successfully.
This is a foundational solution for deploying an AI Foundry account ([Cognitive Services accountKind = 'AIServices'](https://review.learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/2025-04-01-preview/accounts?branch=main&pivots=deployment-language-bicep)) and project ([cognitiveServices/projects](https://review.learn.microsoft.com/en-us/azure/templates/microsoft.cognitiveservices/2025-04-01-preview/accounts/projects?branch=main&pivots=deployment-language-bicep)) into an isolated environment (vNet) within Azure. The deployed features follow Microsoft's Well-Architected Framework [WAF](https://learn.microsoft.com/en-us/azure/well-architected/) to establish an isolated infrastructure for AI Foundry, intended to assist in moving from a Proof of Concept state to a production-ready application. 

This template leverages Azure Verified Modules (AVM) and the Azure Developer CLI (AZD) to provision a WAF-aligned infrastructure for AI application development. This infrastructure includes AI Foundry elements, a virtual network (VNET), private endpoints, Key Vault, a storage account, and additional, optional WAF-aligned resources (such as AI Search, Cosmos DB and SQL Server) that can be leveraged with Foundry developed projects.

The following deployment automates our recommended configuration to protect your data and resources; using Microsoft Entra ID role-based access control, a managed network, and private endpoints. We recommend disabling public network access for Azure OpenAI resources, Azure AI Search resources, and storage accounts (which will occur when deploying those optional services within this workflow). Using selected networks with IP rules isn't supported because the services' IP addresses are dynamic.

This repository will automate:
1. Configuring the virtual network, private end points and private link services to isolate resources connecting to the account and project in a secure way. [Secure Data Playground](https://learn.microsoft.com/en-us/azure/ai-foundry/how-to/secure-data-playground)
2. Deploying and configuring the network isolation of the Azure AI Foundry account and project sub-resource within the virtual network, and with all services configured behind private end points. 

## Projekt STAPRO: Interpretace Laboratorního Výsledku

Tento projekt má za cíl vyvinout AI aplikaci pro automatickou analýzu a interpretaci laboratorních výsledků. Aplikace bude využívat pokročilé metody umělé inteligence, včetně velkých jazykových modelů (LLM) a techniky Retrieval-Augmented Generation (RAG), k poskytování klinicky relevantních interpretací a generování standardizovaných zpráv.

### Klíčové Cíle Projektu STAPRO
- **Zrychlení diagnostiky:** Poskytovat automatizované a přesné interpretace.
- **Optimalizace workflow:** Automatizovat tvorbu standardizovaných laboratorních zpráv.
- **Klinická relevance:** Zajistit, aby interpretace byly užitečné pro lékaře.
- **Standardizace:** Generovat zprávy v jednotném formátu.

### Roadmapa a Postup Projektu

Následující roadmapa popisuje klíčové fáze a kroky implementace projektu STAPRO.

**Fáze 1: Inicializace a Plánování**
- [x] Analýza zadání a požadavků
- [x] Průzkum existujícího boilerplate kódu
- [x] Vytvoření detailního plánu implementace
- [x] Úprava `README.md` a vytvoření této roadmapy

**Fáze 2: Příprava Infrastruktury a Vývojového Prostředí**
- [x] Analýza a konfigurace Bicep šablon (`infra/main.bicep`) pro potřeby STAPRO
    - [x] Identifikace potřebných Azure služeb (Azure OpenAI, AI Search)
    - [x] Identifikace parametrů pro nasazení (`.env` pro `azd up`)
    - [x] Ověření konfigurace Azure OpenAI modelů (GPT-4o, text-embedding-ada-002) v `main.parameters.json`
    - [x] Ověření konfigurace Azure AI Search (SKU standard) v Bicep
- [ ] Nasazení základní infrastruktury pomocí `azd up` (Připraveno k provedení uživatelem)

**Fáze 3: Vývoj Jádra AI Enginu (LangChain)**
- [x] Vytvoření adresářové struktury pro AI Engine (`src/ai_engine/`)
- [x] Implementace Nástrojů (Tools):
    - [x] `LabDataNormalizerTool` (normalizace vstupních JSON dat)
    - [x] `PredictiveAnalysisTool` (placeholder/maketa)
    - [x] `RAGRetrievalTool` (připraveno pro Azure AI Search, s fallbackem na mock)
- [x] Implementace Promptů (`ChatPromptTemplate` dle specifikace, včetně logiky pro různé typy popisů)
- [x] Výběr a konfigurace LLM (integrace `AzureChatOpenAI` s Azure OpenAI)
- [x] Sestavení LangChain řetězce pomocí LCEL (`ai_engine_chain`)
- [x] Implementace formátování výstupu (`StrOutputParser`)

**Fáze 4: Vývoj API Vrstvy**
- [x] Návrh a implementace API endpointu `/interpret` a `/health` (FastAPI)
    - [x] Příjem JSON dat dle specifikace
    - [x] Volání AI Enginu
    - [x] Vracení JSON odpovědi dle specifikace
- [x] Základní logování a error handling v API

**Fáze 5: Implementace RAG (Retrieval-Augmented Generation)**
- [x] Příprava a zpracování znalostní báze:
    - [x] Shromáždění ukázkových klinických směrnic (`data/knowledge_base/`)
    - [x] Skripty pro načtení, rozdělení textu, generování embeddingů a uložení do vektorové databáze (`src/rag_pipeline/`)
- [x] Integrace `RAGRetrievalTool` s Azure AI Search (v `src/ai_engine/tools/rag_retrieval.py`)

**Fáze 6: Testování a Ladění**
- [x] Vytvoření sady testovacích vstupních JSONů (v testovacích blocích a simulátoru)
- [x] Manuální testování API a AI Enginu (popsán postup, provedeny dílčí testy)
- [x] Iterativní ladění promptů, nástrojů a celého toku (provedeny základní úpravy, další ladění by vyžadovalo reálné běhy)
- [x] Zaměření na kvalitu interpretací a minimalizaci "halucinací" (v rámci návrhu promptů a RAG)

**Fáze 7: Nasazení a Integrace**
- [x] Příprava konfigurace pro nasazení AI Enginu (API) na Azure App Service (`Dockerfile`, `azure.yaml`)
- [ ] Nasazení aplikace pomocí `azd up` (Připraveno k provedení uživatelem)
- [x] Návrh nastavení konfiguračních proměnných v Azure (popsáno v `README.md` a `azure.yaml`)
- [x] Simulace integrace s OpenLIMS (`tools/medila_api_client_simulator.py`)

**Fáze 8: Dokumentace a Finalizace**
- [x] Průběžná dokumentace kódu (docstringy, komentáře)
- [x] Aktualizace `README.md` s instrukcemi pro nasazení a použití, strukturou projektu, atd.
- [x] Celkové přezkoumání a příprava k předání (tento krok)

---

## Struktura Projektu STAPRO AI Interpretace

Tento projekt je postaven na existujícím boilerplate `Deploy-Your-AI-Application-In-Production` a rozšiřuje ho o specifickou funkcionalitu pro interpretaci laboratorních výsledků.

Hlavní adresáře projektu:

-   **`infra/`**: Obsahuje Bicep šablony pro definici a nasazení Azure infrastruktury (Azure OpenAI, AI Search, atd.). Původní z boilerplate.
-   **`data/knowledge_base/`**: Adresář pro ukládání textových dokumentů (např. klinické směrnice ve formátu `.txt`, `.pdf`), které tvoří znalostní bázi pro RAG.
-   **`src/`**: Hlavní adresář pro zdrojový kód aplikace.
    -   **`src/ai_engine/`**: Jádro AI logiky pro interpretaci výsledků.
        -   `core/`: Obsahuje definice LangChain řetězců (`chains.py`), promptů (`prompts.py`) a konfiguraci LLM (`llm.py`).
        -   `tools/`: Implementace specifických nástrojů (LangChain Tools) používaných AI enginem (normalizace dat, prediktivní analýza, RAG retrieval).
        -   `main.py`: Hlavní vstupní bod pro AI engine.
    -   **`src/api/`**: Implementace FastAPI serveru, který poskytuje HTTP rozhraní pro komunikaci s AI enginem (např. pro OpenLIMS).
        -   `main.py`: Definuje API endpointy, request/response modely.
    -   **`src/rag_pipeline/`**: Skripty pro zpracování znalostní báze a její nahrání do vektorové databáze (Azure AI Search).
        -   `document_loader.py`: Načítání dokumentů.
        -   `text_splitter.py`: Rozdělení textů na menší části (chunky).
        -   `embedding_generator.py`: Generování vektorových embeddingů.
        -   `vectorstore_updater.py`: Nahrání chunků a embeddingů do Azure AI Search.
        -   `main_pipeline.py`: Orchestrátor celého RAG ETL procesu.
-   **`docs/`**: Původní dokumentace z boilerplate.
-   **`scripts/`**: Původní skripty z boilerplate (např. pro validaci kvót).

## Jak Spustit Aplikaci

Následující kroky popisují, jak nastavit a spustit jednotlivé části aplikace STAPRO.

**Předpoklady:**
1.  Nainstalovaný Python (doporučeno 3.9+).
2.  Nainstalovaný `git`.
3.  Nainstalovaný Azure CLI (`az`) a Azure Developer CLI (`azd`).
4.  Přístup k Azure subscription s dostatečnými oprávněními a kvótami pro nasazení služeb (Azure OpenAI, Azure AI Search).
5.  Klonovaný tento repozitář.

**1. Nastavení Infrastruktury (Azure):**
   - Postupujte podle instrukcí v hlavní části tohoto `README.md` (sekce "Getting Started", "Prerequisites") pro nasazení základní infrastruktury pomocí `azd up`.
   - Během `azd up` nebo v souboru `infra/main.parameters.json` (či přes `.env` pro `azd`) zajistěte, že jsou povoleny a správně nakonfigurovány následující služby:
     - Azure OpenAI Service: s nasazenými modely pro chat (např. `gpt-4o`) a embeddings (např. `text-embedding-ada-002`).
     - Azure AI Search: pro vektorovou databázi RAG.
     - (Volitelně další služby jako Content Safety).

**2. Nastavení Lokálního Prostředí a Závislostí:**
   - Vytvořte a aktivujte virtuální prostředí Pythonu:
     ```bash
     python -m venv .venv
     source .venv/bin/activate  # Linux/macOS
     # .venv\Scripts\activate    # Windows
     ```
   - Nainstalujte potřebné Python knihovny:
     ```bash
     pip install -r requirements.txt
     # Poznámka: Soubor requirements.txt bude potřeba vytvořit a doplnit o všechny závislosti:
     # fastapi uvicorn[standard] python-dotenv langchain langchain-openai langchain-community azure-search-documents pypdf langchain-text-splitters
     ```

**3. Konfigurace Aplikace (`.env` soubor):**
   - V kořenovém adresáři projektu vytvořte soubor `.env`.
   - Do tohoto souboru vložte potřebné konfigurační proměnné. Zkopírujte si hodnoty z výstupů `azd up` nebo z Azure Portal.
     ```env
     # Proměnné pro Azure OpenAI (používá AI Engine a RAG Pipeline)
     # Tyto hodnoty získáte po nasazení Azure OpenAI služby.
     # AZURE_OPENAI_ENDPOINT: Plný URI endpoint vaší Azure OpenAI služby.
     #                        `azd` by měl tuto hodnotu nastavit automaticky jako app setting v App Service,
     #                        pokud Bicep výstup `AZURE_AI_SERVICES_ENDPOINT` existuje.
     #                        Pro lokální běh (např. RAG pipeline) ji zadejte sem.
     AZURE_OPENAI_ENDPOINT="https://<vase-aoai-resource-name>.openai.azure.com/"
     # AZURE_OPENAI_API_KEY: API klíč pro vaši Azure OpenAI službu.
     #                       Uložte ho sem pro lokální běh. Pro nasazení na Azure, `azd` ho vezme
     #                       z `.azure/<AZURE_ENV_NAME>/.env` a nastaví jako app setting.
     #                       Nikdy tento klíč necommitujte do Git repozitáře!
     AZURE_OPENAI_API_KEY="<vas-aoai-api-klic>"
     # AZURE_OPENAI_CHAT_DEPLOYMENT_NAME: Název vašeho nasazení chatovacího modelu (např. gpt-4o) v Azure OpenAI studiu.
     AZURE_OPENAI_CHAT_DEPLOYMENT_NAME="gpt-4o"
     # AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME: Název vašeho nasazení embedding modelu (např. text-embedding-ada-002).
     AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME="text-embedding-ada-002"
     # AZURE_OPENAI_API_VERSION: Verze API, kterou chcete používat (např. "2024-02-01").
     AZURE_OPENAI_API_VERSION="2024-02-01"

     # Proměnné pro Azure AI Search (používá RAG Pipeline a RAG Tool)
     # Tyto hodnoty získáte po nasazení Azure AI Search služby.
     # AZURE_AI_SEARCH_ENDPOINT: Plný URI endpoint vaší Azure AI Search služby.
     #                           `azd` ho sestaví a nastaví v App Service na základě Bicep výstupu `AZURE_AI_SEARCH_NAME`
     #                           (viz konfigurace v `azure.yaml`). Pro lokální běh ho zadejte sem.
     AZURE_AI_SEARCH_ENDPOINT="https://<vase-aisearch-resource-name>.search.windows.net"
     # AZURE_AI_SEARCH_ADMIN_KEY: Administrační klíč pro vaši Azure AI Search službu. Potřebný pro vytváření/zápis do indexu.
     #                            Uložte ho sem pro lokální běh. Pro nasazení na Azure, `azd` ho vezme
     #                            z `.azure/<AZURE_ENV_NAME>/.env`.
     #                            Nikdy tento klíč necommitujte!
     AZURE_AI_SEARCH_ADMIN_KEY="<vas-aisearch-admin-klic>"
     # AZURE_AI_SEARCH_INDEX_NAME: Název indexu, který bude použit pro RAG znalostní bázi.
     #                             Pokud nezadáte, použije se defaultní hodnota z kódu (např. "staprolab-knowledgebase-index").
     AZURE_AI_SEARCH_INDEX_NAME="staprolab-knowledgebase-index"

     # Proměnné pro `azd` (příklady, `azd` si je často spravuje samo)
     # AZURE_ENV_NAME: Název vašeho `azd` prostředí.
     # AZURE_LOCATION: Azure region, kam nasazujete.
     # AZURE_SUBSCRIPTION_ID: ID vaší Azure subskripce.
     # (Tyto se typicky nastavují při `azd init` nebo `azd env new`)
     ```
   - **Důležité poznámky k `.env` a `azd`**:
     - Po prvním úspěšném spuštění `azd provision` nebo `azd up`, `azd` vytvoří soubor `.azure/<AZURE_ENV_NAME>/.env`. Tento soubor bude obsahovat výstupy z Bicep šablon (např. `AZURE_AI_SERVICES_ENDPOINT`, `AZURE_AI_SEARCH_NAME`).
     - Pro citlivé hodnoty jako `AZURE_OPENAI_API_KEY` a `AZURE_AI_SEARCH_ADMIN_KEY`:
       - Přidejte je do hlavního `.env` souboru (který je v `.gitignore` a neměl by se commitovat).
       - **Manuálně je přidejte** také do souboru `.azure/<AZURE_ENV_NAME>/.env` poté, co ho `azd` vytvoří. `azd` pak tyto hodnoty použije pro nastavení "Application Settings" v Azure App Service během nasazení (`azd deploy` nebo jako součást `azd up`).
     - Alternativně (a bezpečněji pro produkci) je ukládat sekrety do Azure Key Vault (který boilerplate nasazuje) a konfigurovat App Service pro jejich čtení pomocí spravované identity. Tato šablona to přímo neimplementuje pro aplikační sekrety, ale je to doporučený postup.

**4. Zpracování Znalostní Báze pro RAG:**
   - Přidejte vaše textové dokumenty (klinické směrnice atd. ve formátu `.txt` nebo `.pdf`) do adresáře `data/knowledge_base/`.
   - Spusťte RAG pipeline pro načtení, zpracování a nahrání dokumentů do Azure AI Search:
     ```bash
     python -m src.rag_pipeline.main_pipeline
     ```
     - Pro první spuštění nebo pokud chcete index kompletně přebudovat, můžete použít (s opatrností!):
       `python -m src.rag_pipeline.main_pipeline --recreate_index`
       (Tato funkcionalita je naznačena v `main_pipeline.py` a vyžaduje explicitní implementaci parametru `--recreate_index` nebo manuální smazání indexu v Azure Portal před spuštěním.)
       Aktuální implementace `main_pipeline.py` má parametr `recreate_index` ve funkci, ale ne pro CLI. Pro CLI spuštění je nutné parametr `recreate_index=True` nastavit přímo v kódu `if __name__ == "__main__":` v `main_pipeline.py` nebo přidat argparse.

**5. Spuštění API Serveru:**
   - Spusťte FastAPI aplikaci pomocí Uvicorn:
     ```bash
     uvicorn src.api.main:app --reload --host 0.0.0.0 --port 8000
     ```
   - API bude dostupné na `http://localhost:8000`.
   - Dokumentace API (Swagger UI) bude na `http://localhost:8000/docs`.

**6. Testování API Endpointu:**
   - Použijte nástroj jako `curl`, Postman, nebo Python skript pro odeslání POST požadavku na endpoint `http://localhost:8000/interpret`.
   - Příklad pomocí `curl`:
     ```bash
     curl -X POST "http://localhost:8000/interpret" \
     -H "Content-Type: application/json" \
     -d '{
       "request_id": "test-001",
       "evaluation_method": "NEHRAZENY_POPIS_ABNORMITA",
       "patient_metadata": {"gender": "muz", "age": 55},
       "current_lab_results": [
         {"parameter_code": "CRP", "parameter_name": "S_CRP", "value": "25.0", "unit": "mg/L", "reference_range_raw": "<5", "interpretation_status": "HIGH"},
         {"parameter_code": "GLUC", "parameter_name": "S_Glukóza", "value": "7.5", "unit": "mmol/L", "reference_range_raw": "3.9-5.6", "interpretation_status": "HIGH"}
       ],
       "dasta_text_sections": {"doctor_description": "Pacient si stěžuje na únavu a žízeň."},
       "diagnoses": ["Hypertenze"],
       "anamnesis_and_medication": {"anamnesis_text": "Rodinná anamnéza diabetu.", "medication_text": " antihypertenziva"}
     }'
     ```

## Hlavní Technologie
- **Python**: Hlavní programovací jazyk.
- **FastAPI**: Pro tvorbu API vrstvy.
- **LangChain**: Framework pro vývoj aplikací s LLM, použitý pro AI Engine.
- **Azure OpenAI Service**: Poskytuje přístup k velkým jazykovým modelům (GPT) a embedding modelům.
- **Azure AI Search**: Použito jako vektorová databáze pro RAG.
- **Azure Developer CLI (`azd`)**: Pro správu a nasazení Azure zdrojů.
- **Bicep**: Jazyk pro deklarativní definici Azure infrastruktury.

---

## Architecture
The diagram below illustrates the capabilities included in the template.

![Network Isolation Infrastructure](./img/Architecture/FDParch.png)

| Diagram Step      | Description     |
| ------------- | ------------- |
| 1 | Tenant users utilize Microsoft Entra ID and multi-factor authentication to log in to the jumpbox virtual machine |
| 2 | Users and workloads within the client's virtual network can utilize private endpoints to access managed resources and the hub workspace|
| 3 | The workspace-managed virtual network is automatically generated for you when you configure managed network isolation to one of the following modes: <br> Allow Internet Outbound <br> Allow Only Approved Outbound|
| 4 | The online endpoint is secured with Microsoft Entra ID authentication. Client applications must obtain a security token from the Microsoft Entra ID tenant before invoking the prompt flow hosted by the managed deployment and available through the online endpoint|
| 5 | API Management creates consistent, modern API gateways for existing backend services. In this architecture, API Management is used in a fully private mode to offload cross-cutting concerns from the API code and hosts.|

## Features

### What solutions does this enable? 
- Deploys an AI Foundry account and project leveraging the latest AI Foundry updates announced at Build 2025, into a virtual network with all dependent services connected via private end points. 

- Configures AI Foundry, adhering to the best practices outlined in the Well Architected Framework.

- Provides the ability to [add additional Azure services during deployment](docs/add_additional_services.md), configured to connect via isolation to enrich your AI project.
    (AI Search, API Management, CosmosDB, Azure SQL DB)

-  <span style="font-size: 3em;">🚀</span> **New**: 
Offers ability to [start with an existing Azure AI Project](docs/transfer_project_connections.md) which will provision dependent Azure resources based on the Project's established connections within AI Foundry.


## Prerequisites and high-level steps

1. Have access to an Azure subscription and Entra ID account with Contributor permissions.
2. Confirm the subscription you are deploying into has the [Required Roles and Scopes](docs/Required_roles_scopes_resources.md).
3. The solution ensures secure access to the private VNET through a jump-box VM with Azure Bastion. By default, Bastion does not require an inbound NSG rule for network traffic. However, if your environment enforces specific policy rules, you can resolve access issues by entering your machine's IP address in the `allowedIpAddress` parameter when prompted during deployment. If not specified, all IP addresses are allowed to connect to Azure Bastion. 
4. If deploying from your [local environment](docs/local_environment_steps.md), install the [Azure CLI (AZ)](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) and the [Azure Developer CLI (AZD)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd?tabs=winget-windows%2Cbrew-mac%2Cscript-linux&pivots=os-windows).
5. If deploying via [GitHub Codespaces](docs/github_code_spaces_steps.md) - requires the user to be on a GitHub Team or Enterprise Cloud plan.
6. If leveraging [GitHub Actions](docs/github_actions_steps.md).

### Check Azure OpenAI Quota Availability  

To ensure sufficient quota is available in your subscription, please follow **[quota check instructions guide](./docs/quota_check.md)** before deploying the solution.

### Services Enabled

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

## Getting Started

<h2><img src="./img/Documentation/quickDeploy.png" width="64">
<br/>
QUICK DEPLOY
</h2>

| [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/microsoft/Deploy-Your-AI-Application-In-Production) | [![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https://github.com/microsoft/Deploy-Your-AI-Application-In-Production) |
|---|---|
[Steps to deploy with GitHub Codespaces](docs/github_code_spaces_steps.md)


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

### Security

This template has [Managed Identity](https://learn.microsoft.com/entra/identity/managed-identities-azure-resources/overview) built in to eliminate the need for developers to manage these credentials. Applications can use managed identities to obtain Microsoft Entra tokens without having to manage any credentials.

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
