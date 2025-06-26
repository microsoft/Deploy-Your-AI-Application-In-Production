# src/rag_pipeline/main_pipeline.py
import os
import time
from dotenv import load_dotenv

from .document_loader import load_documents_from_directory
from .text_splitter import split_documents
from .embedding_generator import get_embedding_model, generate_embeddings_for_documents # Nepoužíváme přímo generate_embeddings_for_documents, pokud spoléháme na add_documents
from .vectorstore_updater import get_vector_store, add_documents_to_vector_store

# Načtení .env souboru pro konfiguraci (API klíče, endpointy)
# Zde se načte, pokud existuje v kořenovém adresáři projektu nebo v aktuálním adresáři.
# Pro konzistentní chování je lepší mít .env v rootu projektu.
dotenv_path = os.path.join(os.path.dirname(__file__), "..", "..", ".env")
if os.path.exists(dotenv_path):
    load_dotenv(dotenv_path)
    print(f".env soubor načten z: {dotenv_path}")
else:
    # Pokud spouštíme z adresáře, kde je .env (např. root projektu), dotenv ho najde automaticky.
    # Tento fallback je pro případ, že by byl spouštěn z jiného místa a .env nebyl v očekávané cestě.
    load_dotenv()
    if os.path.exists(".env"):
         print(".env soubor načten z aktuálního adresáře.")
    else:
        print("WARN: .env soubor nebyl nalezen. Skript nemusí fungovat správně bez konfigurace.")


# Globální konfigurace cesty ke znalostní bázi
# Předpokládáme, že tento skript je v src/rag_pipeline/
# a data jsou v data/knowledge_base/ relativně ke kořeni projektu.
# Získání cesty k adresáři 'data/knowledge_base' relativně ke kořeni projektu
try:
    current_script_path_main = os.path.dirname(os.path.abspath(__file__))
    project_root_main = os.path.abspath(os.path.join(current_script_path_main, "..", ".."))
    DEFAULT_KNOWLEDGE_BASE_DIR = os.path.join(project_root_main, "data", "knowledge_base")
except NameError: # __file__ není definováno např. v interaktivním interpretru
    DEFAULT_KNOWLEDGE_BASE_DIR = os.path.join(os.getcwd(), "data", "knowledge_base")


def run_rag_pipeline(knowledge_base_dir: str = DEFAULT_KNOWLEDGE_BASE_DIR,
                       chunk_size: int = 1000,
                       chunk_overlap: int = 200,
                       recreate_index: bool = False): # Přidán parametr pro smazání indexu
    """
    Spustí kompletní RAG pipeline: načtení, rozdělení, (generování embeddingů - dělá AzureSearch wrapper), nahrání.
    """
    print("--- Spouštění RAG Pipeline ---")
    start_time = time.time()

    # 0. Kontrola existence adresáře znalostní báze
    if not os.path.isdir(knowledge_base_dir):
        print(f"CHYBA: Adresář znalostní báze '{knowledge_base_dir}' neexistuje. Pipeline nemůže pokračovat.")
        return

    try:
        # 1. Načtení dokumentů
        print(f"\nKrok 1: Načítání dokumentů z '{knowledge_base_dir}'...")
        raw_documents = load_documents_from_directory(knowledge_base_dir)
        if not raw_documents:
            print("Nebyly nalezeny žádné dokumenty. Pipeline končí.")
            return
        print(f"Načteno {len(raw_documents)} dokumentů.")

        # 2. Rozdělení dokumentů na chunky
        print("\nKrok 2: Rozdělování dokumentů na chunky...")
        chunks = split_documents(raw_documents, chunk_size=chunk_size, chunk_overlap=chunk_overlap)
        if not chunks:
            print("Nepodařilo se vytvořit žádné chunky. Pipeline končí.")
            return
        print(f"Vytvořeno {len(chunks)} chunků.")

        # 3. Získání embedding modelu
        print("\nKrok 3: Inicializace embedding modelu...")
        embedding_model = get_embedding_model() # Z embedding_generator.py
        print("Embedding model inicializován.")

        # 4. Získání/Vytvoření vektorového úložiště (Azure AI Search)
        print("\nKrok 4: Inicializace vektorového úložiště (Azure AI Search)...")
        vector_store = get_vector_store(embedding_model) # Z vectorstore_updater.py

        if recreate_index:
            index_name_to_delete = os.getenv("AZURE_AI_SEARCH_INDEX_NAME", "staprolab-knowledgebase-index")
            search_endpoint = os.getenv("AZURE_AI_SEARCH_ENDPOINT")
            search_key = os.getenv("AZURE_AI_SEARCH_ADMIN_KEY")
            print(f"Pokus o smazání existujícího indexu '{index_name_to_delete}' (recreate_index=True)...")
            try:
                from azure.search.documents.indexes import SearchIndexClient
                from azure.core.credentials import AzureKeyCredential
                if search_endpoint and search_key and index_name_to_delete:
                    search_client = SearchIndexClient(endpoint=search_endpoint, credential=AzureKeyCredential(search_key))
                    search_client.delete_index(index_name_to_delete)
                    print(f"Index '{index_name_to_delete}' byl úspěšně smazán.")
                else:
                    print("Chybí konfigurace pro smazání indexu (endpoint, klíč nebo název indexu).")
            except Exception as del_e:
                print(f"Nepodařilo se smazat index '{index_name_to_delete}' (možná neexistoval nebo chyba oprávnění): {del_e}")

        print("Vektorové úložiště inicializováno.")

        # 5. Přidání dokumentů (s automatickým generováním embeddingů) do vektorového úložiště
        print("\nKrok 5: Přidávání dokumentů do vektorového úložiště...")
        # Funkce add_documents_to_vector_store použije embedding_model asociovaný s vector_store
        # pro vygenerování embeddingů pro chunky.
        added_ids = add_documents_to_vector_store(chunks, vector_store)
        if not added_ids:
            print("Nepodařilo se přidat žádné dokumenty do vektorového úložiště. Pipeline končí.")
            return

        print(f"\nÚspěšně přidáno/aktualizováno {len(added_ids)} dokumentů/chunků do Azure AI Search.")

    except ValueError as ve:
        print(f"\nCHYBA KONFIGURACE v RAG pipeline: {ve}")
        print("Zkontrolujte .env soubor a nastavení proměnných prostředí pro Azure OpenAI a Azure AI Search.")
    except ImportError as ie:
        print(f"\nCHYBA IMPORTU v RAG pipeline: {ie}")
        print("Ujistěte se, že máte nainstalované všechny potřebné knihovny (např. langchain, langchain-openai, langchain-community, azure-search-documents, pypdf, python-dotenv).")
    except Exception as e:
        print(f"\nDošlo k neočekávané chybě v RAG pipeline: {type(e).__name__} - {e}")
        import traceback
        traceback.print_exc()
    finally:
        end_time = time.time()
        print(f"\n--- RAG Pipeline dokončena za {end_time - start_time:.2f} sekund ---")

if __name__ == "__main__":
    # Spuštění pipeline
    # Ujistěte se, že máte .env soubor v kořenovém adresáři projektu s potřebnými klíči a endpointy
    # pro Azure OpenAI (embedding model) a Azure AI Search.

    # Příklad spuštění:
    # python -m src.rag_pipeline.main_pipeline

    # Pokud chcete při každém spuštění smazat a znovu vytvořit index v Azure AI Search (pro testování):
    # run_rag_pipeline(recreate_index=True)
    # VÝCHOZÍ CHOVÁNÍ JE `recreate_index=False` - nepřemazává existující index.

    run_rag_pipeline(knowledge_base_dir=DEFAULT_KNOWLEDGE_BASE_DIR, recreate_index=False)

    # Můžete také otestovat s jinými parametry:
    # run_rag_pipeline(chunk_size=500, chunk_overlap=50)

    # Pro ověření, zda data byla nahrána, můžete použít Azure Portal k prohlížení indexu
    # v Azure AI Search, nebo spustit testy z vectorstore_updater.py (similarity_search).
