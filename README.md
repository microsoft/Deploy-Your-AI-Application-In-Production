<!---------------------[  Description  ]------------------<recommended> section below------------------>

# STAPRO: AI Interpretace Laboratorních Výsledků (Boilerplate pro Produkční Nasazení)

## Overview

Tento repozitář původně sloužil jako základní šablona (**Deploy your AI Application in Production**) pro nasazení AI Foundry účtu a projektu do izolovaného prostředí v Azure, s důrazem na Well-Architected Framework (WAF). Využívá Azure Verified Modules (AVM) a Azure Developer CLI (AZD).

V rámci projektu **STAPRO (Interpretace Laboratorního Výsledku)** byla tato šablona rozšířena o specifickou AI aplikaci. Cílem projektu STAPRO je automatická analýza a interpretace laboratorních výsledků pomocí LLM a RAG technik.

<span style="font-size: 3em;">🚀</span> **Poznámka k původní šabloně: Updated deployment to match Foundry release at Build 2025!**
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
- [ ] Analýza a konfigurace Bicep šablon (`infra/main.bicep`) pro potřeby STAPRO
    - [ ] Identifikace potřebných Azure služeb (Azure OpenAI, AI Search, CosmosDB/SQL, atd.)
    - [ ] Nastavení parametrů pro nasazení (např. `main.parameters.json` nebo interaktivně přes `azd up`)
    - [ ] Ověření konfigurace Azure OpenAI pro medicínské LLM
    - [ ] Ověření konfigurace Azure AI Search pro vektorové vyhledávání (RAG)
- [ ] Nasazení základní infrastruktury pomocí `azd up`

**Fáze 3: Vývoj Jádra AI Enginu (LangChain)**
- [ ] Vytvoření adresářové struktury pro AI Engine (např. `src/ai_engine/`)
- [ ] Implementace Nástrojů (Tools):
    - [ ] `LabDataNormalizerTool` (normalizace vstupních JSON dat)
    - [ ] `PredictiveAnalysisTool` (placeholder/maketa)
    - [ ] `RAGRetrievalTool` (načítání znalostí, integrace s vektorovou DB)
- [ ] Implementace Promptů (`ChatPromptTemplate` dle specifikace)
- [ ] Výběr a konfigurace LLM (integrace `ChatOpenAI` s Azure OpenAI)
- [ ] Sestavení LangChain Agenta/Chainu (LCEL preferováno)
- [ ] Implementace formátování výstupu (`StrOutputParser`)

**Fáze 4: Vývoj API Vrstvy**
- [ ] Návrh a implementace API endpointu (FastAPI / Azure Functions)
    - [ ] Příjem JSON dat z OpenLIMS
    - [ ] Volání AI Enginu
    - [ ] Vracení JSON odpovědi dle specifikace
- [ ] Základní logování a error handling

**Fáze 5: Implementace RAG (Retrieval-Augmented Generation)**
- [ ] Příprava a zpracování znalostní báze:
    - [ ] Shromáždění ukázkových klinických směrnic
    - [ ] Skripty pro načtení, rozdělení textu, generování embeddingů
    - [ ] Uložení do vektorové databáze (Azure AI Search)
- [ ] Integrace `RAGRetrievalTool` s vektorovou databází

**Fáze 6: Testování a Ladění**
- [ ] Vytvoření sady testovacích vstupních JSONů
- [ ] Manuální a (volitelně) automatizované testování API a AI Enginu
- [ ] Iterativní ladění promptů, nástrojů a celého toku
- [ ] Zaměření na kvalitu interpretací a minimalizaci "halucinací"

**Fáze 7: Nasazení a Integrace**
- [ ] Příprava konfigurace pro nasazení AI Enginu (API) na Azure (Azure Functions, App Service, ACA)
- [ ] Nasazení aplikace pomocí `azd up` (nebo jiných CI/CD pipeline)
- [ ] Nastavení konfiguračních proměnných v Azure
- [ ] Simulace integrace s OpenLIMS (testovací klientský skript)

**Fáze 8: Dokumentace a Finalizace**
- [ ] Průběžná dokumentace kódu a architektury
- [ ] Aktualizace `README.md` s instrukcemi pro nasazení a použití
- [ ] Celkové přezkoumání a příprava k předání

## Komponenty Projektu STAPRO

Aplikace STAPRO se skládá z několika klíčových komponent:

### AI Engine (LangChain)
- **Umístění kódu:** `src/ai_engine/`
- **Popis:** Jádro aplikace, implementované pomocí frameworku LangChain. Využívá model LCEL (LangChain Expression Language) pro orchestraci komplexního řetězce zpracování.
- **Hlavní součásti:**
    - **LLM (Large Language Model):** Využívá `AzureChatOpenAI` pro generování textových interpretací. Konfigurace se nachází v `src/ai_engine/core/llm.py` a spoléhá na proměnné prostředí pro Azure OpenAI (endpoint, klíč, název nasazení).
    - **Prompty:** Strukturované prompty (`ChatPromptTemplate`) definující roli LLM a formát vstupu/výstupu. Nachází se v `src/ai_engine/core/prompts.py`. Obsahuje dynamické vkládání dat a specifické instrukce pro různé typy požadovaných popisů.
    - **Nástroje (Tools):**
        - `LabDataNormalizerTool` (`src/ai_engine/tools/lab_data_normalizer.py`): Normalizuje a validuje vstupní JSON data z OpenLIMS.
        - `PredictiveAnalysisTool` (`src/ai_engine/tools/predictive_analysis.py`): Placeholder pro budoucí integraci prediktivních modelů. Aktuálně vrací mockovaná data.
        - `RAGRetrievalTool` (`src/ai_engine/tools/rag_retrieval.py`): Zajišťuje Retrieval-Augmented Generation. Vyhledává relevantní informace v znalostní bázi (Azure AI Search) na základě dotazu odvozeného z laboratorních dat.
    - **Řetězec (Chain):** Hlavní LCEL řetězec v `src/ai_engine/core/chains.py` spojuje jednotlivé kroky: normalizace dat -> prediktivní analýza (mock) -> RAG vyhledávání -> příprava promptu -> volání LLM.
- **Vstupní bod:** `src/ai_engine/main.py` obsahuje funkci `get_lab_interpretation(raw_json_input_string)`, která přijímá JSON string a vrací textovou interpretaci nebo chybu.

### API Vrstva (FastAPI)
- **Umístění kódu:** `src/api/`
- **Popis:** Poskytuje REST API rozhraní pro komunikaci s externími systémy (např. OpenLIMS).
- **Hlavní součásti (`src/api/main.py`):**
    - **FastAPI aplikace:** Instance FastAPI.
    - **Endpoint `/interpret` (POST):**
        - Přijímá JSON data s laboratorními výsledky (dle Pydantic modelu `InterpretationRequest`).
        - Volá AI Engine (`get_lab_interpretation`) pro zpracování dat.
        - Vrací odpověď ve formátu `InterpretationResponse` (obsahuje `request_id` a buď `interpretation_text` nebo `error`).
    - **Endpoint `/health` (GET):** Pro ověření stavu API.
- **Spuštění:** API server se spouští pomocí Uvicorn, např.: `uvicorn src.api.main:app --reload --host 0.0.0.0 --port 8000` (z kořenového adresáře projektu).

### RAG Data Pipeline
- **Umístění kódu:** `src/rag_pipeline/`
- **Popis:** Sada skriptů pro přípravu a nahrání znalostní báze do vektorové databáze (Azure AI Search) pro potřeby RAG.
- **Hlavní součásti:**
    - `document_loader.py`: Načítá dokumenty (např. `.txt`, `.pdf`) z adresáře `data/knowledge_base/`.
    - `text_splitter.py`: Dělí načtené dokumenty na menší textové chunky.
    - `embedding_generator.py`: Generuje vektorové embeddingy pro chunky pomocí Azure OpenAI embedding modelu (např. `text-embedding-ada-002`).
    - `vectorstore_updater.py`: Vytváří/aktualizuje index v Azure AI Search a nahrává do něj chunky spolu s jejich embeddingy. Definuje schéma indexu včetně vektorových polí a sémantické konfigurace.
    - `main_pipeline.py`: Orchestruje celý proces (načtení -> dělení -> embedding -> nahrání).
- **Spuštění:** Pipeline se spouští skriptem `src/rag_pipeline/main_pipeline.py` (např. `python -m src.rag_pipeline.main_pipeline`). Vyžaduje nastavené proměnné prostředí pro Azure OpenAI a Azure AI Search.
- **Znalostní báze:** Ukázkové dokumenty se nacházejí v `data/knowledge_base/`.

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

## Getting Started (Projekt STAPRO)

Tato sekce popisuje kroky pro spuštění a lokální testování aplikace STAPRO. Pro nasazení na Azure pomocí `azd` se řiďte původní dokumentací šablony (viz níže a složka `docs/`).

### 1. Příprava Prostředí a Závislostí

- **Klonování Repozitáře:**
  ```bash
  git clone <URL_repozitare>
  cd <nazev_repozitare>
  ```
- **Vytvoření Virtuálního Prostředí (doporučeno):**
  ```bash
  python -m venv .venv
  source .venv/bin/activate  # Linux/macOS
  # .venv\Scripts\activate    # Windows
  ```
- **Instalace Závislostí:**
  Všechny potřebné Python knihovny jsou definovány v souboru `requirements.txt`.
  ```bash
  pip install -r requirements.txt
  ```
- **Nastavení Proměnných Prostředí (`.env` soubor):**
  Vytvořte soubor `.env` v kořenovém adresáři projektu. Tento soubor bude obsahovat citlivé údaje a konfiguraci pro připojení k Azure službám. **Tento soubor by neměl být commitován do Git repozitáře!** (Ujistěte se, že je v `.gitignore`).

  Obsah souboru `.env` by měl vypadat následovně (nahraďte placeholder hodnoty `<...>` vašimi skutečnými údaji):
  ```env
  # Azure OpenAI Configuration
  AZURE_OPENAI_ENDPOINT="https://<VASE-OPENAI-SLUZBA>.openai.azure.com/"
  AZURE_OPENAI_API_KEY="<VAS-OPENAI-API-KLIC>"
  AZURE_OPENAI_CHAT_DEPLOYMENT_NAME="gpt-4o" # Nebo název vašeho nasazení LLM (např. gpt-35-turbo)
  AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME="textembed" # Název vašeho nasazení embedding modelu (např. text-embedding-ada-002)
  AZURE_OPENAI_API_VERSION="2024-02-01" # Nebo aktuální podporovaná verze

  # Azure AI Search Configuration
  AZURE_AI_SEARCH_ENDPOINT="https://<VASE-AI-SEARCH-SLUZBA>.search.windows.net"
  AZURE_AI_SEARCH_ADMIN_KEY="<VAS-AI-SEARCH-ADMIN-KLIC>" # Admin klíč pro vytváření/aktualizaci indexů
  AZURE_AI_SEARCH_QUERY_KEY="<VAS-AI-SEARCH-QUERY-KLIC>" # Query klíč (volitelný, pokud se liší od admin)
  AZURE_AI_SEARCH_INDEX_NAME="staprolab-knowledgebase-index" # Výchozí název indexu

  # Původní proměnné pro AZD (pokud plánujete nasazení přes AZD)
  # AZURE_LOCATION="<VASE-AZURE-REGION>" # např. eastus2, westeurope
  # AZURE_SUBSCRIPTION_ID="<ID-VASEHO-AZURE-PREDPLATNEHO>"
  # AZURE_ENV_NAME="staprolabai" # Příklad názvu prostředí pro AZD
  # AZURE_PRINCIPAL_ID="<ID-VASEHO-UZIVATELE-NEBO-SERVICE-PRINCIPAL>" # Pro RBAC
  # AZURE_VM_ADMIN_PASSWORD="<SILNE-HESLO-PRO-VM>" # Pokud používáte VM pro jumpbox
  ```

### 2. Spuštění RAG Data Pipeline
Tato pipeline zpracuje dokumenty z `data/knowledge_base/`, vygeneruje pro ně embeddingy a nahraje je do Azure AI Search. Spouští se z kořenového adresáře projektu:
```bash
python -m src.rag_pipeline.main_pipeline
```
- **Kontrola:** Po úspěšném dokončení ověřte v Azure Portal, že byl vytvořen/aktualizován index v Azure AI Search a že obsahuje data.

### 3. Spuštění API Serveru (FastAPI)
API server poskytuje endpoint pro interpretaci laboratorních výsledků. Spouští se z kořenového adresáře projektu:
```bash
uvicorn src.api.main:app --reload --host 0.0.0.0 --port 8000
```
- Aplikace bude dostupná na `http://localhost:8000`.
- Endpoint `/docs` (např. `http://localhost:8000/docs`) poskytuje automaticky generovanou Swagger/OpenAPI dokumentaci.
- Endpoint `/health` (např. `http://localhost:8000/health`) ověří stav API.

### 4. Testování API
Pro odeslání požadavku na API můžete použít nástroje jako Postman, Insomnia, nebo `curl`, případně Python skript s knihovnou `requests`.

**Příklad POST požadavku na `/interpret`:**
- **URL:** `http://localhost:8000/interpret`
- **Metoda:** `POST`
- **Headers:** `Content-Type: application/json`
- **Body (raw JSON):**
  ```json
  {
    "request_id": "TEST-001",
    "evaluation_method": "NEHRAZENY_POPIS_ABNORMITA",
    "patient_metadata": {
      "gender": "muz",
      "age": 55
    },
    "current_lab_results": [
      {
        "parameter_code": "CRP",
        "parameter_name": "S_CRP",
        "value": "25.0",
        "unit": "mg/L",
        "reference_range_raw": "<5",
        "interpretation_status": "HIGH"
      },
      {
        "parameter_code": "GLUK",
        "parameter_name": "S_Glukóza",
        "value": "5.0",
        "unit": "mmol/L",
        "reference_range_raw": "3.9-5.6",
        "interpretation_status": "NORMAL"
      }
    ],
    "dasta_text_sections": {
      "doctor_description": "Pacient si stěžuje na zvýšenou teplotu a kašel."
    },
    "diagnoses": [],
    "anamnesis_and_medication": {
      "anamnesis_text": "Hypertenze, jinak zdráv.",
      "medication_text": "Prestarium Neo"
    }
  }
  ```

Očekávaná odpověď bude JSON objekt obsahující textovou interpretaci.

---
Původní sekce "Getting Started" pro nasazení pomocí Azure Developer CLI (AZD):

<h2><img src="./img/Documentation/quickDeploy.png" width="64">
<br/>
QUICK DEPLOY (via AZD)
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
