# src/rag_pipeline/embedding_generator.py
import os
from typing import List
from langchain_core.documents import Document
from langchain_openai import AzureOpenAIEmbeddings
from dotenv import load_dotenv

# Načtení proměnných prostředí (pro lokální vývoj)
load_dotenv()

# Konfigurace pro Azure OpenAI Embeddings
# Tyto hodnoty by měly odpovídat nasazené službě Azure OpenAI
AZURE_OPENAI_API_VERSION_EMBEDDINGS = os.getenv("AZURE_OPENAI_API_VERSION", "2024-02-01") # Použijte stejnou nebo kompatibilní verzi jako pro LLM
AZURE_OPENAI_ENDPOINT_EMBEDDINGS = os.getenv("AZURE_OPENAI_ENDPOINT") # Např. https://<your-resource-name>.openai.azure.com/
AZURE_OPENAI_API_KEY_EMBEDDINGS = os.getenv("AZURE_OPENAI_API_KEY")
AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME = os.getenv("AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME", "textembed") # Název nasazení embedding modelu (např. text-embedding-ada-002)
                                                                                                    # V main.parameters.json je to "textembed"

# Maximální počet textů (chunků), které se pošlou najednou do embedding API.
# Pro text-embedding-ada-002 je limit 2048 tokenů na text a Azure API může mít limity na velikost requestu.
# LangChain AzureOpenAIEmbeddings by měl interně řešit batching, ale chunk_size zde
# určuje, kolik dokumentů (textů) se zpracuje v jednom volání metody embed_documents.
# Pro text-embedding-ada-002 je doporučený limit 16 dokumentů na request, pokud jsou krátké.
# Pokud jsou chunky delší (blízko 2048 tokenů), může být potřeba menší batch size.
# Azure OpenAI API má limit 2048 tokenů na vstupní text a max 1MB na request.
# Langchain client pro Azure OpenAI embeddings má `max_retries` a `chunk_size` (počet dokumentů na API call).
# Výchozí chunk_size v Langchain klientovi je často 16.
DEFAULT_EMBEDDING_BATCH_SIZE = 16


def get_embedding_model(batch_size: int = DEFAULT_EMBEDDING_BATCH_SIZE) -> AzureOpenAIEmbeddings:
    """
    Vrací instanci AzureOpenAIEmbeddings nakonfigurovanou pro projekt.
    """
    if not all([AZURE_OPENAI_ENDPOINT_EMBEDDINGS, AZURE_OPENAI_API_KEY_EMBEDDINGS, AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME]):
        raise ValueError("Chybí jedna nebo více konfiguračních proměnných pro Azure OpenAI Embeddings: "
                         "AZURE_OPENAI_ENDPOINT, AZURE_OPENAI_API_KEY, AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME.")

    embedding_model = AzureOpenAIEmbeddings(
        azure_deployment=AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME,
        openai_api_version=AZURE_OPENAI_API_VERSION_EMBEDDINGS,
        azure_endpoint=AZURE_OPENAI_ENDPOINT_EMBEDDINGS,
        api_key=AZURE_OPENAI_API_KEY_EMBEDDINGS,
        chunk_size=batch_size, # Kolik dokumentů se pošle v jednom API volání
        # model="text-embedding-ada-002" # Název modelu je určen nasazením (`azure_deployment`)
    )
    return embedding_model

def generate_embeddings_for_documents(
    documents: List[Document],
    embedding_model: AzureOpenAIEmbeddings
) -> List[List[float]]:
    """
    Generuje vektorové embeddingy pro seznam dokumentů (chunků).

    Args:
        documents (List[Document]): Seznam dokumentů (chunků), pro které se mají generovat embeddingy.
        embedding_model (AzureOpenAIEmbeddings): Instance nakonfigurovaného embedding modelu.

    Returns:
        List[List[float]]: Seznam embeddingů, kde každý embedding je seznam float čísel.
                           Pořadí odpovídá vstupním dokumentům.
                           Vrací prázdný seznam v případě chyby nebo prázdného vstupu.
    """
    if not documents:
        print("Nebyly poskytnuty žádné dokumenty pro generování embeddingů.")
        return []

    texts_to_embed = [doc.page_content for doc in documents]

    try:
        print(f"Generování embeddingů pro {len(texts_to_embed)} textových chunků...")
        embeddings = embedding_model.embed_documents(texts_to_embed)
        print(f"Úspěšně vygenerováno {len(embeddings)} embeddingů.")
        # Každý embedding pro text-embedding-ada-002 by měl mít dimenzi 1536
        # if embeddings:
        #     print(f"  Dimenze prvního embeddingu: {len(embeddings[0])}")
        return embeddings
    except Exception as e:
        print(f"Došlo k chybě při generování embeddingů: {e}")
        # Zde by mohlo být detailnější logování chyby, např. e.response pokud jde o API error
        return []

if __name__ == '__main__':
    print("Testování generování embeddingů...")

    # Pro tento test je nutné mít nastavené proměnné prostředí pro Azure OpenAI
    # (ENDPOINT, API_KEY, název nasazení pro embedding model)
    # Např. AZURE_OPENAI_EMBEDDING_DEPLOYMENT_NAME="textembed"

    # Vytvoření ukázkových dokumentů (chunků)
    sample_chunks = [
        Document(page_content="Toto je první chunk textu určený pro embedding.", metadata={"source": "doc1.txt", "chunk_id": 1}),
        Document(page_content="Druhý chunk obsahuje jiné informace a také bude převeden na vektor.", metadata={"source": "doc1.txt", "chunk_id": 2}),
        Document(page_content="Krátký text.", metadata={"source": "doc2.txt", "chunk_id": 1})
    ]

    try:
        model = get_embedding_model()
        print("Úspěšně inicializován embedding model.")

        # Test generování embeddingu pro jeden dokument (embed_query)
        # query_embedding = model.embed_query("Testovací dotaz pro embedding.")
        # print(f"Embedding pro testovací dotaz (dimenze: {len(query_embedding)}): {query_embedding[:5]}...") # Jen prvních 5 dimenzí

        # Test generování embeddingů pro více dokumentů
        document_embeddings = generate_embeddings_for_documents(sample_chunks, model)

        if document_embeddings and len(document_embeddings) == len(sample_chunks):
            print(f"\nÚspěšně vygenerováno {len(document_embeddings)} embeddingů pro dokumenty.")
            for i, emb in enumerate(document_embeddings):
                print(f"  Embedding pro chunk {i+1} (zdroj: {sample_chunks[i].metadata['source']}):")
                print(f"    Dimenze: {len(emb)}")
                print(f"    Prvních 5 hodnot: {emb[:5]}")
        elif not document_embeddings and sample_chunks:
             print("Nepodařilo se vygenerovat embeddingy, ale dokumenty byly poskytnuty. Zkontrolujte chybové hlášky a konfiguraci Azure OpenAI.")
        else:
            print("Nebyly vygenerovány žádné embeddingy (nebo počet nesouhlasí).")

    except ValueError as ve:
        print(f"Chyba konfigurace: {ve}")
        print("Ujistěte se, že máte správně nastavené proměnné prostředí pro Azure OpenAI (ENDPOINT, API_KEY, název deploymentu pro embeddings).")
    except Exception as e:
        print(f"Neočekávaná chyba při testování embeddingů: {e}")
        print("Zkontrolujte připojení k Azure a kvóty pro embedding model.")

    print("\nTestování s reálnými, rozdělenými dokumenty (vyžaduje předchozí kroky):")
    try:
        from .document_loader import load_documents
        from .text_splitter import split_documents

        real_docs = load_documents() # Načte z data/knowledge_base
        if real_docs:
            real_chunks = split_documents(real_docs)
            if real_chunks:
                print(f"Načteno a rozděleno {len(real_chunks)} reálných chunků.")
                emb_model_for_real = get_embedding_model()
                real_embeddings = generate_embeddings_for_documents(real_chunks, emb_model_for_real)
                if real_embeddings and len(real_embeddings) == len(real_chunks):
                    print(f"Úspěšně vygenerováno {len(real_embeddings)} embeddingů pro reálné chunky.")
                    # Můžeme k dokumentům přidat jejich embeddingy pro další krok
                    for doc, emb in zip(real_chunks, real_embeddings):
                        doc.metadata["embedding"] = emb # Toto je jen pro ukázku, neukládáme takto do Document objektu typicky
                    # print(f"První reálný chunk s embeddingem (prvních 5 dimenzí): {real_chunks[0].metadata['embedding'][:5]}")
                else:
                    print("Nepodařilo se vygenerovat embeddingy pro reálné chunky.")
            else:
                print("Reálné dokumenty nebyly rozděleny.")
        else:
            print("Nebyly načteny žádné reálné dokumenty pro test embeddingů.")

    except ImportError:
        print("Nepodařilo se importovat document_loader nebo text_splitter. Spusťte testy jednotlivě.")
    except ValueError as ve:
        print(f"Chyba konfigurace při testu s reálnými dokumenty: {ve}")
    except Exception as e:
        print(f"Chyba při testu s reálnými dokumenty: {e}")
