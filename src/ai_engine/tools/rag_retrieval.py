# src/ai_engine/tools/rag_retrieval.py
import os
import json
from typing import Type, Dict, Any, List
from langchain_core.tools import BaseTool, tool
from pydantic import BaseModel, Field
from dotenv import load_dotenv

from langchain_openai import AzureOpenAIEmbeddings
from azure.core.credentials import AzureKeyCredential
from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizedQuery

# Načtení proměnných prostředí
load_dotenv()

# Konfigurace pro Azure AI Search a Embeddings (měly by být již načteny díky load_dotenv)
AZURE_AI_SEARCH_ENDPOINT = os.getenv("AZURE_AI_SEARCH_ENDPOINT")
AZURE_AI_SEARCH_API_KEY = os.getenv("AZURE_AI_SEARCH_QUERY_KEY", os.getenv("AZURE_AI_SEARCH_ADMIN_KEY")) # Preferujeme query key, pokud je definován
AZURE_AI_SEARCH_INDEX_NAME = os.getenv("AZURE_AI_SEARCH_INDEX_NAME", "staprolab-knowledgebase-index")

AZURE_OPENAI_API_VERSION_EMBEDDINGS = os.getenv("AZURE_OPENAI_API_VERSION", "2024-02-01")
AZURE_OPENAI_ENDPOINT_EMBEDDINGS = os.getenv("AZURE_OPENAI_ENDPOINT")
AZURE_OPENAI_API_KEY_EMBEDDINGS = os.getenv("AZURE_OPENAI_API_KEY")
AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME = os.getenv("AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME", "textembed")

# Globální instance pro klienty, aby se neinicializovaly při každém volání
# Toto je zjednodušení; v produkční aplikaci by se správa klientů řešila robustněji (např. dependency injection)
_search_client_instance = None
_embedding_model_instance = None

def get_embedding_model_instance() -> AzureOpenAIEmbeddings:
    global _embedding_model_instance
    if _embedding_model_instance is None:
        if not all([AZURE_OPENAI_ENDPOINT_EMBEDDINGS, AZURE_OPENAI_API_KEY_EMBEDDINGS, AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME]):
            raise ValueError("Chybí konfigurace pro Azure OpenAI Embeddings v RAG tool.")
        _embedding_model_instance = AzureOpenAIEmbeddings(
            azure_deployment=AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME,
            openai_api_version=AZURE_OPENAI_API_VERSION_EMBEDDINGS,
            azure_endpoint=AZURE_OPENAI_ENDPOINT_EMBEDDINGS,
            api_key=AZURE_OPENAI_API_KEY_EMBEDDINGS,
            chunk_size=16 # Výchozí pro Langchain klienta, lze upravit
        )
    return _embedding_model_instance

def get_search_client_instance() -> SearchClient:
    global _search_client_instance
    if _search_client_instance is None:
        if not all([AZURE_AI_SEARCH_ENDPOINT, AZURE_AI_SEARCH_API_KEY, AZURE_AI_SEARCH_INDEX_NAME]):
            raise ValueError("Chybí konfigurace pro Azure AI Search v RAG tool.")
        _search_client_instance = SearchClient(
            endpoint=AZURE_AI_SEARCH_ENDPOINT,
            index_name=AZURE_AI_SEARCH_INDEX_NAME,
            credential=AzureKeyCredential(AZURE_AI_SEARCH_API_KEY)
        )
    return _search_client_instance


class RAGInput(BaseModel):
    query: str = Field(description="Dotaz nebo klíčová slova pro vyhledávání v znalostní bázi (např. název parametru, identifikované riziko).")
    top_k: int = Field(default=3, description="Počet nejrelevantnějších dokumentů k vrácení.")

@tool("rag_retrieval_tool", args_schema=RAGInput, return_direct=False)
def retrieve_clinical_guidelines_func(query: str, top_k: int = 3) -> str:
    """
    Vyhledává relevantní klinické směrnice a odborné informace z vektorové databáze
    (Azure AI Search) na základě zadaného dotazu.
    Nejprve převede dotaz na embedding a poté provede vektorové vyhledávání.
    Vrací spojený text nalezených dokumentů.
    """
    try:
        embedding_model = get_embedding_model_instance()
        search_client = get_search_client_instance()
    except ValueError as e:
        print(f"Chyba inicializace klientů v RAG tool: {e}")
        return f"Chyba konfigurace RAG: {e}. Zkontrolujte proměnné prostředí."

    if not query:
        return "Nebyl poskytnut žádný dotaz pro RAG."

    try:
        print(f"RAG Tool: Přijat dotaz: '{query}', top_k: {top_k}")
        query_embedding = embedding_model.embed_query(query)
        print(f"RAG Tool: Dotaz převeden na embedding (dim: {len(query_embedding)}).")

        vector_query = VectorizedQuery(
            vector=query_embedding,
            k_nearest_neighbors=top_k,
            fields="content_vector" # Pole obsahující vektory
        )

        results = search_client.search(
            search_text=None, # Můžeme kombinovat s full-text: query, ale pro čistý RAG stačí vektorové
            vector_queries=[vector_query],
            select=["source", "content", "start_index"], # Pole, která chceme vrátit
            # query_type="semantic", # Pro sémantické reranking, pokud je index takto konfigurován
            # semantic_configuration_name="my-semantic-config",
            top=top_k
        )

        found_docs_content = []
        print(f"RAG Tool: Nalezeno výsledků (před zpracováním):")
        for i, result in enumerate(results):
            # Logování detailů každého výsledku
            # print(f"  Výsledek {i+1}: ID={result.get('id', 'N/A')}, Zdroj={result.get('source', 'N/A')}, Skóre={result.get('@search.score', 'N/A')}")
            # print(f"    Obsah (část): {result.get('content', '')[:100]}...")

            # Přidání obsahu dokumentu do seznamu
            # Můžeme přidat i metadata, pokud chceme, aby LLM viděl např. zdroj
            doc_info = f"Zdroj: {result.get('source', 'N/A')}"
            # doc_info += f" (Pozice v dokumentu: {result.get('start_index', 'N/A')})" # Volitelné
            doc_info += f"\nObsah: {result.get('content', '')}"
            found_docs_content.append(doc_info)

        if not found_docs_content:
            print(f"RAG Tool: Pro dotaz '{query}' nebyly nalezeny žádné relevantní dokumenty v Azure AI Search.")
            return f"Pro dotaz '{query}' nebyly ve znalostní bázi nalezeny žádné specifické informace."

        print(f"RAG Tool: Počet nalezených a formátovaných dokumentů: {len(found_docs_content)}")
        return "\n\n---\n\n".join(found_docs_content) # Oddělení dokumentů

    except Exception as e:
        print(f"Chyba při provádění RAG vyhledávání: {e}")
        import traceback
        traceback.print_exc()
        return f"Došlo k chybě při vyhledávání ve znalostní bázi: {str(e)}"

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
