# src/rag_pipeline/main_pipeline.py
import os
from dotenv import load_dotenv

# Importy z ostatních modulů v tomto balíčku
from .document_loader import load_documents, DEFAULT_KNOWLEDGE_BASE_DIR
from .text_splitter import split_documents, DEFAULT_CHUNK_SIZE, DEFAULT_CHUNK_OVERLAP
from .embedding_generator import get_embedding_model, generate_embeddings_for_documents
from .vectorstore_updater import (
    get_search_index_client,
    get_search_client,
    create_or_update_index,
    upload_documents_to_vector_store,
    AZURE_AI_SEARCH_INDEX_NAME # Importujeme výchozí název indexu
)

def run_rag_data_pipeline(
    knowledge_base_dir: str = DEFAULT_KNOWLEDGE_BASE_DIR,
    chunk_size: int = DEFAULT_CHUNK_SIZE,
    chunk_overlap: int = DEFAULT_CHUNK_OVERLAP,
    index_name: str = AZURE_AI_SEARCH_INDEX_NAME
):
    """
    Spustí kompletní RAG data pipeline:
    1. Načte dokumenty z adresáře.
    2. Rozdělí dokumenty na chunky.
    3. Vygeneruje embeddingy pro chunky.
    4. Vytvoří/aktualizuje index v Azure AI Search.
    5. Nahraje chunky a jejich embeddingy do Azure AI Search.
    """
    print("--- Spouštění RAG Data Pipeline ---")

    # Načtení .env souboru pro případ, že skript běží samostatně
    # V produkčním nasazení by proměnné prostředí měly být nastaveny systémově.
    load_dotenv()

    # Ověření, zda jsou nastaveny potřebné proměnné prostředí pro Azure služby
    # (Endpointy, klíče pro OpenAI a AI Search)
    # Toto je základní kontrola, detailnější kontroly jsou v jednotlivých modulech.
    required_env_vars = [
        "AZURE_OPENAI_ENDPOINT", "AZURE_OPENAI_API_KEY", "AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME",
        "AZURE_AI_SEARCH_ENDPOINT", "AZURE_AI_SEARCH_ADMIN_KEY"
    ]
    missing_vars = [var for var in required_env_vars if not os.getenv(var)]
    if missing_vars:
        print(f"Chyba: Chybí následující povinné proměnné prostředí: {', '.join(missing_vars)}")
        print("Pipeline nemůže pokračovat. Nastavte prosím tyto proměnné.")
        return False

    try:
        # Krok 1: Načtení dokumentů
        print(f"\n[Krok 1/5] Načítání dokumentů z '{knowledge_base_dir}'...")
        documents = load_documents(knowledge_base_dir)
        if not documents:
            print("Nebyly nalezeny žádné dokumenty. Pipeline končí.")
            return False
        print(f"Načteno {len(documents)} dokumentů.")

        # Krok 2: Dělení dokumentů na chunky
        print(f"\n[Krok 2/5] Dělení dokumentů na chunky (velikost: {chunk_size}, překryv: {chunk_overlap})...")
        chunks = split_documents(documents, chunk_size=chunk_size, chunk_overlap=chunk_overlap)
        if not chunks:
            print("Nepodařilo se rozdělit dokumenty na chunky. Pipeline končí.")
            return False
        print(f"Dokumenty rozděleny na {len(chunks)} chunků.")

        # Krok 3: Generování embeddingů
        print("\n[Krok 3/5] Generování embeddingů pro chunky...")
        embedding_model = get_embedding_model() # Použije výchozí batch size
        embeddings_list = generate_embeddings_for_documents(chunks, embedding_model)
        if not embeddings_list or len(embeddings_list) != len(chunks):
            print("Nepodařilo se vygenerovat embeddingy pro všechny chunky. Pipeline končí.")
            return False
        print(f"Vygenerováno {len(embeddings_list)} embeddingů.")

        # Krok 4: Příprava Azure AI Search (vytvoření/aktualizace indexu)
        print(f"\n[Krok 4/5] Příprava Azure AI Search indexu '{index_name}'...")
        index_client = get_search_index_client()
        create_or_update_index(index_client, index_name)
        # Poznámka: get_search_client() vrací klienta s index_name z proměnné prostředí,
        # pokud chceme použít `index_name` z argumentu funkce, museli bychom ho předat.
        # Pro konzistenci, pokud je index_name parametr, měl by se použít i pro search_client.
        search_client = get_search_client() # Použije AZURE_AI_SEARCH_INDEX_NAME, pokud index_name není předán explicitně
        # Pokud chceme dynamický název indexu i pro search_client:
        if index_name != AZURE_AI_SEARCH_INDEX_NAME:
             search_client = SearchClient(endpoint=os.getenv("AZURE_AI_SEARCH_ENDPOINT"),
                                         index_name=index_name,
                                         credential=AzureKeyCredential(os.getenv("AZURE_AI_SEARCH_ADMIN_KEY")))


        # Krok 5: Nahrání dokumentů a embeddingů do Azure AI Search
        print(f"\n[Krok 5/5] Nahrávání chunků a embeddingů do indexu '{search_client.index_name}'...")
        upload_documents_to_vector_store(search_client, chunks, embeddings_list)

        print("\n--- RAG Data Pipeline byla úspěšně dokončena. ---")
        return True

    except ValueError as ve:
        print(f"Chyba konfigurace v pipeline: {ve}")
        return False
    except Exception as e:
        print(f"Došlo k neočekávané chybě během RAG Data Pipeline: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == '__main__':
    # Tento skript lze spustit pro naplnění/aktualizaci vektorové databáze.
    # Ujistěte se, že máte .env soubor s potřebnými klíči a endpointy,
    # nebo že jsou proměnné prostředí nastaveny jinak.

    print("Spouštění RAG Data Pipeline z __main__...")

    # Příklad spuštění s výchozími hodnotami
    success = run_rag_data_pipeline()

    if success:
        print("\nPipeline proběhla úspěšně.")
    else:
        print("\nPipeline selhala nebo byla přerušena kvůli chybě.")

    # Příklad spuštění s vlastním názvem indexu (pokud by to bylo potřeba)
    # print("\nSpouštění RAG Data Pipeline s vlastním názvem indexu...")
    # custom_index_name = "staprolab-kb-test-custom"
    # success_custom = run_rag_data_pipeline(index_name=custom_index_name)
    # if success_custom:
    #     print(f"Pipeline pro index '{custom_index_name}' proběhla úspěšně.")
    # else:
    #     print(f"Pipeline pro index '{custom_index_name}' selhala.")
