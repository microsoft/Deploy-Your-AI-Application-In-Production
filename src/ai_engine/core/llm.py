# src/ai_engine/core/llm.py
import os
from langchain_openai import AzureChatOpenAI
from dotenv import load_dotenv

# Načtení proměnných prostředí (pokud používáte .env soubor lokálně)
load_dotenv()

# Konfigurace Azure OpenAI LLM
# Tyto hodnoty by měly být bezpečně spravovány, např. pomocí Azure Key Vault v produkci
# Pro lokální vývoj mohou být v .env souboru nebo přímo nastaveny jako proměnné prostředí

AZURE_OPENAI_API_VERSION = os.getenv("AZURE_OPENAI_API_VERSION", "2024-02-01") # Doporučeno použít nejnovější stabilní verzi
AZURE_OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT") # Např. https://<your-resource-name>.openai.azure.com/
AZURE_OPENAI_API_KEY = os.getenv("AZURE_OPENAI_API_KEY")
AZURE_OPENAI_CHAT_DEPLOYMENT_NAME = os.getenv("AZURE_OPENAI_CHAT_DEPLOYMENT_NAME") # Název vašeho nasazení modelu GPT (např. gpt-4o)

def get_llm(temperature: float = 0.1, max_tokens: int = 2000):
    """
    Vrací instanci AzureChatOpenAI nakonfigurovanou pro projekt.
    """
    if not all([AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_API_KEY, AZURE_OPENAI_CHAT_DEPLOYMENT_NAME]):
        raise ValueError("Chybí jedna nebo více konfiguračních proměnných pro Azure OpenAI: "
                         "AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_API_KEY, AZURE_OPENAI_CHAT_DEPLOYMENT_NAME")

    llm = AzureChatOpenAI(
        azure_deployment=AZURE_OPENAI_CHAT_DEPLOYMENT_NAME,
        openai_api_version=AZURE_OPENAI_API_VERSION,
        azure_endpoint=AZURE_OPENAI_ENDPOINT,
        api_key=AZURE_OPENAI_API_KEY,
        temperature=temperature,
        max_tokens=max_tokens,
        # model_kwargs={"response_format": {"type": "json_object"}}, # Pokud byste chtěli JSON output, ale pro textovou interpretaci to není nutné
    )
    return llm

if __name__ == '__main__':
    # Příklad použití a test připojení (vyžaduje nastavené proměnné prostředí)
    try:
        llm_instance = get_llm()
        print("Úspěšně vytvořena instance AzureChatOpenAI.")
        # Příklad jednoduchého volání (může vyžadovat prompt)
        # from langchain_core.messages import HumanMessage
        # response = llm_instance.invoke([HumanMessage(content="Ahoj, jak se máš?")])
        # print("Odpověď od LLM:", response.content)
    except ValueError as e:
        print(f"Chyba při inicializaci LLM: {e}")
    except Exception as e:
        print(f"Neočekávaná chyba: {e}")
