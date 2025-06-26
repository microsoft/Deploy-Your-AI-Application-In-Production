# src/rag_pipeline/vectorstore_updater.py
import os
from typing import List
from langchain_core.documents import Document
from langchain_openai import AzureOpenAIEmbeddings
from langchain_community.vectorstores.azure_search import AzureSearch, AzureSearchVectorStoreMode
from dotenv import load_dotenv

# Načtení proměnných prostředí
load_dotenv()

# Konfigurace pro Azure AI Search (názvy sjednoceny s azure.yaml)
AZURE_AI_SEARCH_ENDPOINT = os.getenv("AZURE_AI_SEARCH_ENDPOINT")
AZURE_AI_SEARCH_ADMIN_KEY = os.getenv("AZURE_AI_SEARCH_ADMIN_KEY")
AZURE_AI_SEARCH_INDEX_NAME = os.getenv("AZURE_AI_SEARCH_INDEX_NAME", "staprolab-knowledgebase-index")

# Konfigurace pro Azure OpenAI Embeddings je také potřeba pro AzureSearch wrapper,
# i když primárně používáme předanou instanci `embedding_model`.
# LangChain AzureSearch interně může potřebovat nakonfigurovat embeddings pro některé operace.
# Zajistíme, že jsou zde definovány, i když hlavní instance se předává.
AZURE_OPENAI_API_VERSION = os.getenv("AZURE_OPENAI_API_VERSION", "2024-02-01")
AZURE_OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT")
AZURE_OPENAI_API_KEY = os.getenv("AZURE_OPENAI_API_KEY")
AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME = os.getenv("AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME")


def get_vector_store(embedding_model: AzureOpenAIEmbeddings) -> AzureSearch:
    """
    Vrací instanci AzureSearch (vektorové úložiště) nakonfigurovanou pro projekt.
    Pokud index neexistuje, pokusí se ho vytvořit při prvním přidání dokumentů.
    """
    if not all([AZURE_AI_SEARCH_ENDPOINT, AZURE_AI_SEARCH_ADMIN_KEY, AZURE_AI_SEARCH_INDEX_NAME]):
        raise ValueError(
            "Chybí jedna nebo více konfiguračních proměnných pro Azure AI Search: "
            "AZURE_AI_SEARCH_ENDPOINT, AZURE_AI_SEARCH_ADMIN_KEY, AZURE_AI_SEARCH_INDEX_NAME. "
            "Zkontrolujte .env soubor nebo proměnné prostředí (měly by být nastaveny `azd`em)."
        )
    if not embedding_model: # Instance embedding modelu je předána
        raise ValueError("Nebyl poskytnut embedding model pro AzureSearch.")

    # Dimenze embedding modelu - důležité pro vytvoření indexu, pokud neexistuje
    # Pro text-embedding-ada-002 je to 1536
    # Pro text-embedding-3-small je to 1536
    # Pro text-embedding-3-large je to 3072
    # Zkusíme to zjistit z modelu, pokud je to možné, jinak default.
    # Případně by to mělo být konfigurovatelné.
    # Prozatím předpokládáme 1536 (ada-002 nebo 3-small).
    # Pokud je embedding_model instance AzureOpenAIEmbeddings, nemá přímý atribut `dimensions`.
    # Musíme to vědět na základě nasazeného modelu.
    # V `azure.yaml` máme `text-embedding-ada-002`, což má 1536.
    # Pokud byste změnili model v `main.parameters.json`, museli byste upravit i zde.
    embedding_dimensions = 1536
    if AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME and "text-embedding-3-large" in AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME:
        embedding_dimensions = 3072

    print(f"Používám dimenzi embeddingu: {embedding_dimensions} pro index '{AZURE_AI_SEARCH_INDEX_NAME}'.")

    # Konfigurace pro LangChain AzureSearch, aby správně vytvořil index, pokud neexistuje.
    # Toto zajistí, že `content_vector` pole je správně definováno.
    # `embedding_function` je použita pro `embed_query` a pokud by se volalo `add_texts`.
    # My voláme `add_documents`, ale Langchain ji stále potřebuje pro interní konzistenci.
    vector_store = AzureSearch(
        azure_search_endpoint=AZURE_AI_SEARCH_ENDPOINT,
        azure_search_key=AZURE_AI_SEARCH_ADMIN_KEY, # Používáme admin klíč pro možnost vytváření indexu
        index_name=AZURE_AI_SEARCH_INDEX_NAME,
        embedding_function=embedding_model.embed_query,
        # Explicitně definujeme sémantická pole a vektorový profil pro případ, že index neexistuje
        # Langchain se pokusí vytvořit index s touto konfigurací.
        fields=[ # Toto je příklad, Langchain si vytvoří svá defaultní pole, pokud není specifikováno.
                 # Pro kontrolu je lepší nechat Langchain vytvořit defaultní a případně upravit index v Azure.
        ],
        vector_store_mode=AzureSearchVectorStoreMode.HYBRID, # Umožňuje hybridní vyhledávání (vektor + text)
        # Další parametry pro konfiguraci vektorového vyhledávání v Azure AI Search:
        # search_type="hybrid", # Toto je spíše pro query time
        # semantic_configuration_name="my-semantic-config", # Pokud máte sémantickou konfiguraci
        # vector_field_name="content_vector", # Defaultně Langchain použije toto
        # Dimenze se nastaví automaticky, pokud Langchain vytváří index a zná embedding_function.
        # Ale pro jistotu můžeme specifikovat:
        # vector_embedding_dimension=embedding_dimensions
        # Toto se zdá být řešeno interně v Langchainu na základě embedding_function.
    )
    # Poznámka: Pokud Azure Search index již existuje, LangChain se ho pokusí použít.
    # Pokud schéma neodpovídá (např. chybí pole content_vector nebo má špatnou dimenzi),
    # může dojít k chybám při nahrávání nebo vyhledávání.
    # Pro produkci je nejlepší mít schéma indexu definované a spravované explicitně (např. Bicep, SDK).
    return vector_store

def add_documents_to_vector_store(
    documents: List[Document],
    vector_store: AzureSearch,
    # embeddings: List[List[float]] # Pokud bychom chtěli explicitně předávat embeddingy
                                   # LangChain AzureSearch.add_documents si je typicky generuje sám
                                   # pomocí embedding_function definované ve vector_store
) -> List[str]:
    """
    Přidá dokumenty (chunky) do Azure AI Search vektorového úložiště.
    LangChain AzureSearch wrapper si sám vygeneruje embeddingy pomocí `embedding_function`
    asociované s `vector_store` instancí.

    Args:
        documents: Seznam dokumentů (chunků) k přidání.
        vector_store: Instance AzureSearch vektorového úložiště.

    Returns:
        Seznam ID přidaných dokumentů.
    """
    if not documents:
        print("Nebyly poskytnuty žádné dokumenty k přidání do vektorového úložiště.")
        return []

    print(f"Přidávání {len(documents)} dokumentů do Azure AI Search indexu: {AZURE_AI_SEARCH_INDEX_NAME}...")

    # LangChain AzureSearch.add_documents si interně zavolá embed_documents na textech z `documents`.
    # Metadata se také ukládají. Ujistěte se, že metadata jsou serializovatelná.
    # `id` pro každý dokument v Azure Search se typicky generuje LangChainem (hash obsahu),
    # nebo můžeme zkusit nastavit vlastní `ids` argument v `add_documents`.

    # Připravíme metadata tak, aby byla všechna string (AI Search může mít problém s různými typy v 'metadata' poli)
    for doc in documents:
        if doc.metadata and isinstance(doc.metadata, dict):
            # Přidáme název souboru do hlavních metadat, pokud není
            if 'source' not in doc.metadata and 'source' in doc.metadata.get('metadata', {}):
                 doc.metadata['source'] = str(doc.metadata['metadata']['source'])

            # Převedeme vše vnořené v 'metadata' na stringy, pokud je to slovník
            # AzureSearch v Langchain ukládá celý dict z doc.metadata do pole "metadata" jako string,
            # ale pokud máme definovaná extra pole jako "source", tak ta se mapují přímo.
            # Zjednodušení: hlavní metadata pole necháme tak, jak je, Langchain to serializuje.

            # Ujistíme se, že 'source' je přítomno a je to string.
            if 'source' not in doc.metadata:
                doc.metadata['source'] = "Neznámý zdroj" # Fallback
            else:
                doc.metadata['source'] = str(doc.metadata['source'])


    try:
        # `add_documents` očekává, že embedding_function je nastavena v AzureSearch instanci.
        # Tato funkce se použije na `doc.page_content`.
        added_ids = vector_store.add_documents(documents=documents)
        print(f"Úspěšně přidáno/aktualizováno {len(added_ids)} dokumentů do Azure AI Search.")
        # print(f"Příklad ID přidaných dokumentů: {added_ids[:5]}")
        return added_ids
    except Exception as e:
        print(f"Chyba při přidávání dokumentů do Azure AI Search: {e}")
        # Zde může být potřeba detailnější error handling, např. pokud selže vytvoření indexu
        # nebo pokud data neodpovídají schématu indexu.
        raise

if __name__ == '__main__':
    # Příklad použití
    # Tento test vyžaduje, aby Azure OpenAI (pro embeddings) a Azure AI Search služby byly nasazeny
    # a konfigurační proměnné správně nastaveny v .env nebo prostředí.

    print("--- Testování Vector Store Updater ---")

    # Mockované dokumenty (chunky)
    mock_chunk_docs = [
        Document(page_content="CRP je marker zánětu.", metadata={"source": "smernice_crp.txt", "chunk_seq_num": 1}),
        Document(page_content="Zvýšené CRP může signalizovat infekci.", metadata={"source": "smernice_crp.txt", "chunk_seq_num": 2, "custom_field": "hodnotaA"}),
        Document(page_content="PSA se používá pro screening karcinomu prostaty.", metadata={"source": "smernice_psa.txt", "chunk_seq_num": 1, "custom_field": "hodnotaB"}),
        Document(page_content="Benigní hyperplazie prostaty také zvyšuje PSA.", metadata={"source": "smernice_psa.txt", "chunk_seq_num": 2}),
    ]

    try:
        # 1. Získání embedding modelu
        if not all([AZURE_OPENAI_ENDPOINT_VS, AZURE_OPENAI_API_KEY_VS, AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME_VS]):
            raise ValueError("Chybí konfigurace pro Azure OpenAI Embeddings pro test vector_store_updater.")

        embedding_model_instance = AzureOpenAIEmbeddings(
            azure_deployment=AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME_VS,
            openai_api_version=AZURE_OPENAI_API_VERSION_VS,
            azure_endpoint=AZURE_OPENAI_ENDPOINT_VS,
            api_key=AZURE_OPENAI_API_KEY_VS,
            chunk_size=1
        )
        print("Embedding model instance vytvořena.")

        # 2. Získání/vytvoření vector store
        vector_store_instance = get_vector_store(embedding_model_instance)
        print(f"Vector store instance pro index '{AZURE_AI_SEARCH_INDEX_NAME}' získána/vytvořena.")

        # 3. Přidání dokumentů do vector store
        # Předpokládá se, že index buď neexistuje (a LangChain ho vytvoří se základními poli + vektorovým polem),
        # nebo existuje a má kompatibilní schéma (včetně vektorového pole a profilu).
        # Pokud index existuje, ale nemá správná pole (např. 'content_vector'), může dojít k chybě.

        # Pro test smažeme index, pokud existuje, aby se vytvořil znovu s očekávanou strukturou.
        # V PRODUKCI TOTO NEDĚLEJTE!
        # try:
        #     from azure.search.documents.indexes import SearchIndexClient
        #     from azure.core.credentials import AzureKeyCredential
        #     if AZURE_AI_SEARCH_ENDPOINT and AZURE_AI_SEARCH_KEY and AZURE_AI_SEARCH_INDEX_NAME:
        #         search_client = SearchIndexClient(endpoint=AZURE_AI_SEARCH_ENDPOINT, credential=AzureKeyCredential(AZURE_AI_SEARCH_KEY))
        #         search_client.delete_index(AZURE_AI_SEARCH_INDEX_NAME)
        #         print(f"Test: Index '{AZURE_AI_SEARCH_INDEX_NAME}' byl smazán pro účely testu.")
        # except Exception as del_e:
        #     print(f"Test: Nepodařilo se smazat index '{AZURE_AI_SEARCH_INDEX_NAME}' (možná neexistoval): {del_e}")


        added_document_ids = add_documents_to_vector_store(mock_chunk_docs, vector_store_instance)

        if added_document_ids:
            print(f"\nDokumenty úspěšně přidány/aktualizovány. Počet: {len(added_document_ids)}.")
            print(f"Příklad ID: {added_document_ids[:5]}")

            # Test vyhledávání (ověření, že data byla nahrána)
            print("\nTest vyhledávání podobnosti:")
            query = "Co je CRP?"
            # Použijeme metodu `similarity_search` z LangChain wrapperu
            # Ta interně použije `embedding_function` (pro query) a provede vektorové vyhledávání.
            results = vector_store_instance.similarity_search(query=query, k=2) # Najdi 2 nejbližší
            if results:
                print(f"Nalezeno {len(results)} výsledků pro dotaz '{query}':")
                for i, res_doc in enumerate(results):
                    print(f"  Výsledek {i+1}:")
                    print(f"    Obsah: {res_doc.page_content[:100]}...")
                    print(f"    Metadata: {res_doc.metadata}")
            else:
                print(f"Pro dotaz '{query}' nebyly nalezeny žádné výsledky.")
        else:
            print("Nepodařilo se přidat dokumenty do vektorového úložiště.")

    except ValueError as ve:
        print(f"Chyba konfigurace: {ve}")
        print("Ujistěte se, že máte správně nastavené proměnné prostředí v .env souboru pro:")
        print("- Azure OpenAI Embeddings (AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_API_KEY, AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME)")
        print("- Azure AI Search (AZURE_AI_SEARCH_ENDPOINT, AZURE_AI_SEARCH_ADMIN_KEY, AZURE_AI_SEARCH_INDEX_NAME)")
    except Exception as e:
        print(f"Došlo k neočekávané chybě během testu vector_store_updater: {type(e).__name__} - {e}")
        import traceback
        traceback.print_exc()

    print("\n--- Test s prázdným seznamem dokumentů ---")
    try:
        if not all([AZURE_OPENAI_ENDPOINT_VS, AZURE_OPENAI_API_KEY_VS, AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME_VS]):
             raise ValueError("Chybí konfigurace pro Azure OpenAI Embeddings pro test s prázdnými dokumenty.")
        embedding_model_for_empty_test = AzureOpenAIEmbeddings(
            azure_deployment=AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME_VS,
            openai_api_version=AZURE_OPENAI_API_VERSION_VS,
            azure_endpoint=AZURE_OPENAI_ENDPOINT_VS,
            api_key=AZURE_OPENAI_API_KEY_VS
        )
        vector_store_for_empty_test = get_vector_store(embedding_model_for_empty_test)
        empty_ids = add_documents_to_vector_store([], vector_store_for_empty_test)
        print(f"Počet ID z prázdného vstupu: {len(empty_ids)}")
    except ValueError as ve:
        print(f"Chyba konfigurace pro test s prázdnými dokumenty: {ve}")
    except Exception as e:
        print(f"Neočekávaná chyba při testu s prázdnými dokumenty: {e}")
