# src/ai_engine/tools/rag_retrieval.py
from typing import Type, Dict, Any, List
from langchain_core.tools import BaseTool, tool
from pydantic import BaseModel, Field

import os
from typing import Type, Dict, Any, List
from langchain_core.tools import BaseTool, tool
from pydantic import BaseModel, Field
from dotenv import load_dotenv

# Načtení .env, pokud existuje, pro konfiguraci Azure služeb
dotenv_path = os.path.join(os.path.dirname(__file__), "..", "..", ".env")
if os.path.exists(dotenv_path):
    load_dotenv(dotenv_path)
else:
    load_dotenv()


import os
from typing import Type, Dict, Any, List
from langchain_core.tools import BaseTool, tool
from pydantic import BaseModel, Field
from dotenv import load_dotenv

# Načtení .env, pokud existuje, pro konfiguraci Azure služeb
# Cesta je relativní ke kořenovému adresáři projektu, odkud se typicky spouští `azd` nebo `uvicorn`.
# Pokud spouštíme tento soubor přímo (např. pro testování nástroje), dotenv by měl najít .env v rootu.
if not load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), "..", "..", ".env")):
    load_dotenv() # Zkusí načíst z aktuálního adresáře, pokud výše uvedené selže nebo neexistuje

# Pokus o import komponent pro skutečný RAG
# Názvy proměnných pro embedding model a vector store jsou sjednoceny.
RAG_ENABLED = False
MOCK_KNOWLEDGE_BASE = {
    "hyperglykémie": "MOCK_FALLBACK: Hyperglykémie (zvýšená hladina cukru v krvi) může být příznakem diabetu.",
    "crp": "MOCK_FALLBACK: C-reaktivní protein (CRP) je marker zánětu.",
    "psa": "MOCK_FALLBACK: Prostatický specifický antigen (PSA) se používá pro screening karcinomu prostaty.",
    "hcg": "MOCK_FALLBACK: Lidský choriogonadotropin (hCG) je hormon produkovaný v těhotenství.",
}

try:
    # Tyto importy musí být uvnitř try-except, protože závisí na konfiguraci,
    # která nemusí být vždy dostupná (např. při unit testech bez .env).
    from src.rag_pipeline.embedding_generator import get_embedding_model
    from src.rag_pipeline.vectorstore_updater import get_vector_store

    # Ověření, zda jsou potřebné proměnné prostředí skutečně nastaveny
    # Toto je důležité, protože samotný import může projít, i když proměnné chybí,
    # ale následné volání get_embedding_model() nebo get_vector_store() by selhalo.
    if all([
        os.getenv("AZURE_OPENAI_ENDPOINT"),
        os.getenv("AZURE_OPENAI_API_KEY"),
        os.getenv("AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME"),
        os.getenv("AZURE_AI_SEARCH_ENDPOINT"),
        os.getenv("AZURE_AI_SEARCH_ADMIN_KEY"),
        os.getenv("AZURE_AI_SEARCH_INDEX_NAME")
    ]):
        RAG_ENABLED = True
        print("INFO: RAGRetrievalTool je nakonfigurován pro použití Azure AI Search.")
    else:
        print("WARN: Některé konfigurační proměnné pro RAG chybí. RAGRetrievalTool bude používat mockovaná data.")
        RAG_ENABLED = False

except ImportError as e:
    print(f"WARN: Nepodařilo se importovat komponenty pro skutečný RAG: {e}. RAGRetrievalTool bude používat mockovaná data.")
    RAG_ENABLED = False
except ValueError as e: # Chyba z get_embedding_model nebo get_vector_store, pokud chybí proměnné
    print(f"WARN: Chyba při inicializaci RAG komponent (pravděpodobně chybějící konfigurace): {e}. RAGRetrievalTool bude používat mockovaná data.")
    RAG_ENABLED = False


class RAGInput(BaseModel):
    query: str = Field(description="Dotaz nebo klíčová slova pro vyhledávání v znalostní bázi (např. název parametru, identifikované riziko).")

@tool("rag_retrieval_tool", args_schema=RAGInput, return_direct=False)
def retrieve_clinical_guidelines_func(query: str) -> str:
    """
    Vyhledává relevantní klinické směrnice a odborné články ze znalostní báze
    (Azure AI Search). Pokud Azure AI Search není dostupný, nakonfigurovaný,
    nebo pokud selže inicializace, použije mockovaná data.
    """
    global RAG_ENABLED # Umožníme modifikaci, pokud by inicializace selhala až zde

    if RAG_ENABLED:
        try:
            print(f"RAG dotaz (Azure AI Search): {query}")
            # Získání modelů zde, uvnitř try-except, pro případ, že by selhala konfigurace až při volání
            embedding_model_instance = get_embedding_model()
            vector_store_instance = get_vector_store(embedding_model_instance)

            results = vector_store_instance.similarity_search_with_score(
                query=query,
                k=3,
            )

            if results:
                context_parts = []
                for doc, score in results:
                    source = doc.metadata.get('source', 'Neznámý zdroj')
                    content_preview = doc.page_content.replace('\n', ' ').strip()[:250]
                    # Zahrneme skóre do kontextu, aby LLM případně mohl zvážit relevanci
                    context_parts.append(f"Zdroj: {source} (Relevance: {score:.2f})\nObsah:\n{doc.page_content}")
                    print(f"RAG výsledek: Zdroj: {source}, Skóre: {score:.2f}, Náhled: {content_preview}...")

                if not context_parts:
                     return f"Nebyly nalezeny dostatečně relevantní informace pro dotaz: '{query}'."
                return "\n\n---\n\n".join(context_parts)
            else:
                return f"Pro dotaz '{query}' nebyly v znalostní bázi (Azure AI Search) nalezeny žádné relevantní informace."
        except Exception as e:
            print(f"CHYBA při dotazování Azure AI Search v RAGRetrievalTool: {e}. Přepínám na mockovaná data pro tento dotaz.")
            RAG_ENABLED = False # Pro tento běh, aby se nezkoušelo znovu
            # Fallback na mockovaná data i zde, pokud selže skutečný RAG
            # return f"Došlo k chybě při přístupu ke znalostní bázi. ({type(e).__name__})"
            # Nyní se provede kód níže pro mockovaná data.

    # Tento blok se provede, pokud RAG_ENABLED bylo False od začátku, nebo pokud selhala výše uvedená výjimka
    if not RAG_ENABLED:
        print(f"RAGRetrievalTool používá mockovaná data pro dotaz: '{query}'.")
        query_lower = query.lower()
        relevant_docs_mock = []
        for keyword, text in MOCK_KNOWLEDGE_BASE.items():
            if keyword in query_lower: # Jednoduchá shoda klíčového slova
                relevant_docs_mock.append(text)

        if not relevant_docs_mock: # Fallback, pokud ani mock neobsahuje nic
            # Zkusíme obecnější klíčová slova z dotazu
            for word in query_lower.split():
                if word in MOCK_KNOWLEDGE_BASE:
                    relevant_docs_mock.append(MOCK_KNOWLEDGE_BASE[word])
                    break # Vezmeme první shodu
            if not relevant_docs_mock:
                 return f"MOCK: Nebyly nalezeny žádné specifické směrnice pro dotaz: '{query}'."

        return "\n\n".join(list(set(relevant_docs_mock))) # list(set(...)) pro odstranění duplicit

class RAGRetrievalTool(BaseTool):
    name: str = "rag_retrieval_tool"
    description: str = (
        "Vyhledává relevantní klinické směrnice, medicínské informace a odborné články "
        "ze znalostní báze na základě zadaného dotazu (např. název laboratorního testu, "
        "symptom, identifikované riziko). Použij pro získání kontextu k interpretaci výsledků."
    )
    args_schema: Type[BaseModel] = RAGInput
    return_direct: bool = False

    def _run(self, query: str) -> str:
        return retrieve_clinical_guidelines_func(query)

    async def _arun(self, query: str) -> str:
        return self._run(query)

if __name__ == '__main__':
    # Použití funkce
    retrieved_info_crp = retrieve_clinical_guidelines_func("S_CRP")
    print(f"Info pro CRP:\n{retrieved_info_crp}\n")

    retrieved_info_psa = retrieve_clinical_guidelines_func("Prostatický specifický antigen (PSA) a jeho význam")
    print(f"Info pro PSA:\n{retrieved_info_psa}\n")

    retrieved_info_unknown = retrieve_clinical_guidelines_func("NeznámýTermín")
    print(f"Info pro neznámý termín:\n{retrieved_info_unknown}\n")

    # Použití nástroje
    tool_instance_rag = RAGRetrievalTool()
    retrieved_tool_hcg = tool_instance_rag.invoke({"query": "hCG v těhotenství"})
    print(f"Info pro hCG (nástroj):\n{retrieved_tool_hcg}\n")
