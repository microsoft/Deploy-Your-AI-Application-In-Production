# src/rag_pipeline/vectorstore_updater.py
import os
from typing import List
from langchain_core.documents import Document
from langchain_openai import AzureOpenAIEmbeddings # Použito pro typovou anotaci a případně pro získání dimenze
from azure.core.credentials import AzureKeyCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.models import VectorizedQuery
from azure.search.documents.indexes.models import (
    SearchIndex,
    SearchField,
    SearchFieldDataType,
    SimpleField,
    SearchableField,
    VectorSearch,
    VectorSearchProfile,
    HnswAlgorithmConfiguration,
    SemanticSearch,
    SemanticField,
    SemanticConfiguration,
    SemanticPrioritizedFields
)
from dotenv import load_dotenv

# Načtení proměnných prostředí
load_dotenv()

# Konfigurace pro Azure AI Search
AZURE_AI_SEARCH_ENDPOINT = os.getenv("AZURE_AI_SEARCH_ENDPOINT") # Např. https://<your-search-service-name>.search.windows.net
AZURE_AI_SEARCH_API_KEY = os.getenv("AZURE_AI_SEARCH_ADMIN_KEY") # Admin klíč pro vytváření/aktualizaci indexů
AZURE_AI_SEARCH_INDEX_NAME = os.getenv("AZURE_AI_SEARCH_INDEX_NAME", "staprolab-knowledgebase-index")

# Dimenze embeddingů - pro text-embedding-ada-002 je to 1536
# Měla by být konzistentní s modelem použitým v embedding_generator.py
EMBEDDING_DIMENSION = 1536 # text-embedding-ada-002

def get_search_index_client() -> SearchIndexClient:
    if not all([AZURE_AI_SEARCH_ENDPOINT, AZURE_AI_SEARCH_API_KEY]):
        raise ValueError("Chybí konfigurace pro Azure AI Search: ENDPOINT nebo ADMIN_KEY.")
    return SearchIndexClient(endpoint=AZURE_AI_SEARCH_ENDPOINT, credential=AzureKeyCredential(AZURE_AI_SEARCH_API_KEY))

def get_search_client() -> SearchClient:
    if not all([AZURE_AI_SEARCH_ENDPOINT, AZURE_AI_SEARCH_API_KEY, AZURE_AI_SEARCH_INDEX_NAME]):
        raise ValueError("Chybí konfigurace pro Azure AI Search: ENDPOINT, ADMIN_KEY nebo INDEX_NAME.")
    return SearchClient(endpoint=AZURE_AI_SEARCH_ENDPOINT, index_name=AZURE_AI_SEARCH_INDEX_NAME, credential=AzureKeyCredential(AZURE_AI_SEARCH_API_KEY))

def create_or_update_index(index_client: SearchIndexClient, index_name: str):
    """
    Vytvoří nebo aktualizuje index v Azure AI Search pro ukládání dokumentů a jejich embeddingů.
    """
    fields = [
        SimpleField(name="id", type=SearchFieldDataType.String, key=True, filterable=True), # Unikátní ID dokumentu/chunku
        SearchableField(name="content", type=SearchFieldDataType.String, searchable=True, analyzable=True), # Textový obsah chunku
        SearchField(name="content_vector", type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
                      searchable=True, vector_search_dimensions=EMBEDDING_DIMENSION, vector_search_profile_name="my-hnsw-profile"),
        SimpleField(name="source", type=SearchFieldDataType.String, filterable=True, facetable=True), # Zdrojový soubor
        SimpleField(name="category", type=SearchFieldDataType.String, filterable=True, facetable=True, default_value="general"), # Kategorie (pokud je)
        SimpleField(name="start_index", type=SearchFieldDataType.Int32, filterable=True, sortable=True, default_value=0), # Pozice v původním dokumentu
        # Další metadata lze přidat podle potřeby
    ]

    vector_search = VectorSearch(
        algorithms=[HnswAlgorithmConfiguration(name="my-hnsw-algo")], # Můžeme mít více algoritmů
        profiles=[VectorSearchProfile(name="my-hnsw-profile", algorithm_configuration_name="my-hnsw-algo")]
    )

    # Sémantické vyhledávání (volitelné, ale doporučené pro lepší relevanci)
    # Vyžaduje, aby služba AI Search byla na úrovni Basic nebo vyšší a v podporovaném regionu.
    semantic_search_config = SemanticSearch(configurations=[
        SemanticConfiguration(
            name="my-semantic-config",
            prioritized_fields=SemanticPrioritizedFields(
                title_field=None, # Nemáme explicitní titulkové pole pro chunky
                content_fields=[SemanticField(field_name="content")]
            )
        )
    ])

    index = SearchIndex(
        name=index_name,
        fields=fields,
        vector_search=vector_search,
        semantic_search=semantic_search_config # Přidání sémantické konfigurace
    )

    try:
        print(f"Vytváření/aktualizace indexu '{index_name}'...")
        index_client.create_or_update_index(index)
        print(f"Index '{index_name}' je připraven.")
    except Exception as e:
        print(f"Chyba při vytváření/aktualizaci indexu '{index_name}': {e}")
        raise

def upload_documents_to_vector_store(
    search_client: SearchClient,
    documents: List[Document],
    embeddings: List[List[float]]
):
    """
    Nahraje dokumenty (chunky) a jejich embeddingy do Azure AI Search.
    Předpokládá, že index již existuje a má správnou strukturu.
    """
    if len(documents) != len(embeddings):
        raise ValueError("Počet dokumentů a embeddingů se neshoduje.")
    if not documents:
        print("Nebyly poskytnuty žádné dokumenty k nahrání.")
        return

    docs_to_upload = []
    for i, (doc, emb) in enumerate(zip(documents, embeddings)):
        # Vytvoření unikátního ID pro každý chunk, např. kombinací zdroje a indexu/hashe
        # Pro jednoduchost použijeme source a start_index, pokud je dostupné
        source_name = doc.metadata.get("source", f"unknown_source_{i}")
        start_idx = doc.metadata.get("start_index", i)
        doc_id = f"{os.path.basename(source_name)}-{start_idx}"
        # Nahrazení nevalidních znaků pro ID
        doc_id = "".join(c if c.isalnum() or c in ['-', '_'] else '_' for c in doc_id)


        docs_to_upload.append({
            "id": doc_id,
            "content": doc.page_content,
            "content_vector": emb,
            "source": doc.metadata.get("source", "N/A"),
            "category": doc.metadata.get("category", "general"),
            "start_index": doc.metadata.get("start_index", 0)
        })

    try:
        print(f"Nahrávání {len(docs_to_upload)} dokumentů do indexu '{search_client.index_name}'...")
        # upload_documents může přijmout seznam slovníků
        result = search_client.upload_documents(documents=docs_to_upload)

        successful_uploads = sum(1 for r in result if r.succeeded)
        print(f"Úspěšně nahráno {successful_uploads} z {len(docs_to_upload)} dokumentů.")

        for item_result in result:
            if not item_result.succeeded:
                print(f"  Chyba při nahrávání dokumentu ID {item_result.key}: {item_result.error_message}")

    except Exception as e:
        print(f"Došlo k chybě při nahrávání dokumentů: {e}")
        # Zde by mohlo být detailnější logování
        raise

# Funkce pro vyhledávání (pro testování a pro RAGRetrievalTool)
def perform_vector_search(query_text: str, query_embedding: List[float], search_client: SearchClient, top_k: int = 3) -> List[Dict[str, Any]]:
    """
    Provede vektorové vyhledávání v Azure AI Search.
    """
    vector_query = VectorizedQuery(vector=query_embedding, k_nearest_neighbors=top_k, fields="content_vector")

    try:
        results = search_client.search(
            search_text=None, # Můžeme kombinovat s full-text vyhledáváním: query_text,
            vector_queries=[vector_query],
            select=["id", "source", "content", "start_index"], # Která pole chceme vrátit
            # query_type="semantic", # Pokud chceme použít sémantické reranking
            # semantic_configuration_name="my-semantic-config", # Název sémantické konfigurace
            top=top_k
        )

        found_docs = []
        for result in results:
            found_docs.append({
                "id": result.get("id"),
                "score": result.get("@search.score"), # Relevance score pro full-text
                "vector_score": result.get("@search.score"), # Prozatím, AI Search vrací jedno skóre, v budoucnu se může lišit
                "reranker_score": result.get("@search.reranker_score"), # Pokud je použit semantic search
                "content": result.get("content"),
                "source": result.get("source"),
                "start_index": result.get("start_index")
            })
        return found_docs
    except Exception as e:
        print(f"Chyba při vektorovém vyhledávání: {e}")
        return []


if __name__ == '__main__':
    print("Testování Azure AI Search Vector Store Updater...")

    # Pro tento test je nutné mít nastavené proměnné prostředí:
    # AZURE_AI_SEARCH_ENDPOINT, AZURE_AI_SEARCH_ADMIN_KEY
    # a také pro embedding model (AZURE_OPENAI_ENDPOINT, atd.)

    # Krok 1: Načtení, rozdělení a embeddování dokumentů (z předchozích skriptů)
    try:
        from .document_loader import load_documents
        from .text_splitter import split_documents
        from .embedding_generator import get_embedding_model, generate_embeddings_for_documents

        print("\n--- Fáze 1: Načítání a příprava dokumentů ---")
        docs = load_documents() # Z data/knowledge_base
        if not docs:
            raise Exception("Nebyly načteny žádné dokumenty z data/knowledge_base. Ukončuji test.")

        chunks = split_documents(docs)
        if not chunks:
            raise Exception("Dokumenty nebyly rozděleny na chunky. Ukončuji test.")

        emb_model = get_embedding_model()
        embeddings_list = generate_embeddings_for_documents(chunks, emb_model)
        if not embeddings_list or len(embeddings_list) != len(chunks):
            raise Exception("Nepodařilo se vygenerovat embeddingy pro všechny chunky. Ukončuji test.")

        print(f"Připraveno {len(chunks)} chunků s embeddingy.")

        # Krok 2: Vytvoření/aktualizace indexu a nahrání dokumentů
        print("\n--- Fáze 2: Práce s Azure AI Search ---")
        idx_client = get_search_index_client()
        s_client = get_search_client() # Pro nahrávání a vyhledávání

        create_or_update_index(idx_client, AZURE_AI_SEARCH_INDEX_NAME)
        upload_documents_to_vector_store(s_client, chunks, embeddings_list)

        print("\n--- Fáze 3: Testovací vyhledávání ---")
        test_query = "Jaké jsou referenční hodnoty pro CRP u dospělých?"
        print(f"Testovací dotaz: {test_query}")

        query_vector = emb_model.embed_query(test_query)

        search_results = perform_vector_search(test_query, query_vector, s_client, top_k=2)

        if search_results:
            print(f"Nalezeno {len(search_results)} výsledků pro dotaz:")
            for res_doc in search_results:
                print(f"  ID: {res_doc['id']}, Zdroj: {res_doc['source']}")
                print(f"  Skóre: {res_doc.get('score', 'N/A')}, Vektorové skóre: {res_doc.get('vector_score', 'N/A')}, Reranker skóre: {res_doc.get('reranker_score', 'N/A')}")
                print(f"  Obsah (část): {res_doc['content'][:150]}...")
                print("-" * 20)
        else:
            print("Pro testovací dotaz nebyly nalezeny žádné výsledky.")

    except ValueError as ve:
        print(f"Chyba konfigurace: {ve}")
        print("Ujistěte se, že máte správně nastavené proměnné prostředí pro Azure AI Search a Azure OpenAI.")
    except ImportError:
        print("Chyba importu. Ujistěte se, že všechny potřebné skripty jsou dostupné.")
    except Exception as e:
        print(f"Neočekávaná chyba v testovacím scénáři: {e}")
        import traceback
        traceback.print_exc()
