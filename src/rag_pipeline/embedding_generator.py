# src/rag_pipeline/embedding_generator.py
import os
from typing import List
from langchain_core.documents import Document
from langchain_openai import AzureOpenAIEmbeddings
from dotenv import load_dotenv

# Načtení proměnných prostředí (pokud používáte .env soubor lokálně)
# Tyto proměnné by měly být nastaveny v prostředí, kde běží `azd up` nebo `python -m src.rag_pipeline.main_pipeline`
load_dotenv()

# Názvy proměnných sjednoceny s azure.yaml a očekávanými výstupy z `azd env get-values`
AZURE_OPENAI_API_VERSION = os.getenv("AZURE_OPENAI_API_VERSION", "2024-02-01")
AZURE_OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT") # Očekává ${AZURE_AI_SERVICES_ENDPOINT} z azd
AZURE_OPENAI_API_KEY = os.getenv("AZURE_OPENAI_API_KEY")
AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME = os.getenv("AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME")

def get_embedding_model() -> AzureOpenAIEmbeddings:
    """
    Vrací instanci AzureOpenAIEmbeddings nakonfigurovanou pro projekt.
    """
    if not all([AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_API_KEY, AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME]):
        raise ValueError(
            "Chybí jedna nebo více konfiguračních proměnných pro Azure OpenAI Embeddings: "
            "AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_API_KEY, AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME. "
            "Zkontrolujte .env soubor nebo proměnné prostředí (měly by být nastaveny `azd`em)."
        )

    embedding_model = AzureOpenAIEmbeddings(
        azure_deployment=AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME,
        openai_api_version=AZURE_OPENAI_API_VERSION,
        azure_endpoint=AZURE_OPENAI_ENDPOINT,
        api_key=AZURE_OPENAI_API_KEY,
        chunk_size=1 # Pro ada-002 je doporučeno 16, ale pro novější modely (v3) může být 1. Pro jistotu 1.
                     # Langchain defaultně batchuje requesty, takže `chunk_size` zde určuje, kolik textů se pošle v jednom requestu do modelu.
                     # Větší `chunk_size` (až do limitu modelu, např. 16 pro ada-002) může být efektivnější.
    )
    return embedding_model

def generate_embeddings_for_documents(documents: List[Document], embedding_model: AzureOpenAIEmbeddings) -> List[List[float]]:
    """
    Generuje vektorové embeddingy pro seznam dokumentů (chunků).

    Args:
        documents: Seznam dokumentů (chunků), pro které se mají generovat embeddingy.
        embedding_model: Instance embedding modelu.

    Returns:
        Seznam embeddingů (každý embedding je seznam float čísel).
    """
    if not documents:
        print("Nebyly poskytnuty žádné dokumenty pro generování embeddingů.")
        return []

    print(f"Generování embeddingů pro {len(documents)} dokumentů/chunků...")

    texts_to_embed = [doc.page_content for doc in documents]

    try:
        embeddings = embedding_model.embed_documents(texts_to_embed)
        print(f"Úspěšně vygenerováno {len(embeddings)} embeddingů.")
        # print(f"Dimenze prvního embeddingu: {len(embeddings[0]) if embeddings else 'N/A'}")
        return embeddings
    except Exception as e:
        print(f"Chyba při generování embeddingů: {e}")
        # Zde by mohlo být detailnější logování chyby nebo pokus o opakování pro jednotlivé dokumenty.
        # Pro jednoduchost nyní vracíme prázdný seznam.
        raise # Znovu vyvoláme chybu, aby ji volající mohl zpracovat

if __name__ == '__main__':
    # Příklad použití
    # Tento test vyžaduje, aby Azure OpenAI služba a embedding model byly nasazeny a
    # konfigurační proměnné správně nastaveny v .env nebo prostředí.

    print("--- Testování Embedding Generatoru ---")

    # Vytvoření mockovaných dokumentů pro test
    mock_docs = [
        Document(page_content="Toto je první testovací dokument o C-reaktivním proteinu."),
        Document(page_content="Druhý dokument se zabývá problematikou PSA a jeho významem v diagnostice."),
        Document(page_content="Krátký text."),
    ]

    try:
        emb_model = get_embedding_model()
        print(f"Použitý embedding model: {AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME}")

        document_embeddings = generate_embeddings_for_documents(mock_docs, emb_model)

        if document_embeddings:
            print(f"\nVygenerováno {len(document_embeddings)} embeddingů.")
            for i, emb in enumerate(document_embeddings):
                print(f"Embedding pro dokument {i+1} (prvních 5 dimenzí): {emb[:5]}... (Celková dimenze: {len(emb)})")
        else:
            print("Nepodařilo se vygenerovat žádné embeddingy.")

    except ValueError as ve:
        print(f"Chyba konfigurace: {ve}")
        print("Ujistěte se, že máte správně nastavené proměnné prostředí pro Azure OpenAI Embeddings v .env souboru:")
        print("- AZURE_OPENAI_ENDPOINT")
        print("- AZURE_OPENAI_API_KEY")
        print("- AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME (např. text-embedding-ada-002)")
    except Exception as e:
        print(f"Došlo k neočekávané chybě během testu embedding generatoru: {e}")

    print("\nTest s prázdným seznamem dokumentů:")
    try:
        emb_model_for_empty_test = get_embedding_model() # Znovu, aby se ověřila konfigurace i zde
        empty_embeddings = generate_embeddings_for_documents([], emb_model_for_empty_test)
        print(f"Počet embeddingů z prázdného vstupu: {len(empty_embeddings)}")
    except ValueError as ve:
        print(f"Chyba konfigurace pro test s prázdnými dokumenty: {ve}")
    except Exception as e:
        print(f"Neočekávaná chyba při testu s prázdnými dokumenty: {e}")
