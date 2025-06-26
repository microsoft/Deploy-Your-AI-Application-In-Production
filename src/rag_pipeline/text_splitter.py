# src/rag_pipeline/text_splitter.py
from typing import List
from langchain_core.documents import Document
from langchain.text_splitter import RecursiveCharacterTextSplitter, CharacterTextSplitter # Přidán CharacterTextSplitter pro jednoduchost

# Doporučené hodnoty pro chunk_size a chunk_overlap se mohou lišit
# v závislosti na povaze textů a použitém embedding modelu.
# Pro modely jako text-embedding-ada-002 je dobré mít chunky,
# které nejsou příliš krátké ani příliš dlouhé.
DEFAULT_CHUNK_SIZE = 1000  # Počet znaků na chunk
DEFAULT_CHUNK_OVERLAP = 200 # Počet znaků překryvu mezi chunky

def split_documents(
    documents: List[Document],
    chunk_size: int = DEFAULT_CHUNK_SIZE,
    chunk_overlap: int = DEFAULT_CHUNK_OVERLAP
) -> List[Document]:
    """
    Rozdělí seznam LangChain dokumentů na menší části (chunky).

    Args:
        documents (List[Document]): Seznam dokumentů k rozdělení.
        chunk_size (int): Maximální velikost jednoho chunku (v počtu znaků).
        chunk_overlap (int): Počet znaků překryvu mezi sousedními chunky.

    Returns:
        List[Document]: Seznam rozdělených dokumentů (chunků).
                       Každý chunk je také LangChain Document objekt,
                       který si typicky zachovává metadata původního dokumentu.
    """
    if not documents:
        print("Nebyly poskytnuty žádné dokumenty k rozdělení.")
        return []

    # Použijeme RecursiveCharacterTextSplitter, který se snaží dělit text
    # na základě sady oddělovačů (např. "\n\n", "\n", " ", "") a udržovat
    # sémanticky související části textu pohromadě.
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        length_function=len, # Funkce pro měření délky textu (standardně len)
        add_start_index=True, # Přidá do metadat pozici začátku chunku v původním dokumentu
        separators=["\n\n", "\n", ". ", ", ", " ", ""] # Preferované oddělovače
    )

    # Alternativně, pro velmi jednoduché texty nebo specifické případy:
    # text_splitter = CharacterTextSplitter(
    #     separator="\n\n", # Například dělení podle odstavců
    #     chunk_size=chunk_size,
    #     chunk_overlap=chunk_overlap,
    #     length_function=len,
    #     add_start_index=True,
    # )

    try:
        split_docs = text_splitter.split_documents(documents)
        print(f"Původních {len(documents)} dokumentů bylo rozděleno na {len(split_docs)} chunků.")

        # Příklad informací o chuncích
        # for i, chunk_doc in enumerate(split_docs[:3]): # Jen prvních pár
        #     print(f"  Chunk {i+1} (zdroj: {chunk_doc.metadata.get('source', 'N/A')}):")
        #     print(f"    Začátek na indexu: {chunk_doc.metadata.get('start_index', 'N/A')}")
        #     print(f"    Obsah (část): {chunk_doc.page_content[:100]}...")

        return split_docs
    except Exception as e:
        print(f"Došlo k chybě při dělení dokumentů: {e}")
        return []

if __name__ == '__main__':
    print("Testování dělení dokumentů...")

    # Vytvoření ukázkových dokumentů pro test
    doc1_content = "Toto je první dokument. Má několik vět. Bude rozdělen na menší části. " * 50
    doc2_content = "Druhý dokument je kratší. Ale také obsahuje důležité informace. " * 30

    sample_documents = [
        Document(page_content=doc1_content, metadata={"source": "doc1.txt", "category": "test"}),
        Document(page_content=doc2_content, metadata={"source": "doc2.txt", "category": "test"}),
        Document(page_content="Krátký dokument.", metadata={"source": "doc3.txt"}) # Tento by neměl být moc dělen
    ]

    print(f"Počet vstupních dokumentů: {len(sample_documents)}")
    for i, doc in enumerate(sample_documents):
        print(f"  Dokument {i+1} (zdroj: {doc.metadata['source']}), délka: {len(doc.page_content)} znaků.")

    # Test s výchozími parametry
    print("\nTest s výchozími parametry (chunk_size=1000, chunk_overlap=200):")
    chunks_default = split_documents(sample_documents)
    if chunks_default:
        print(f"Celkem vytvořeno chunků: {len(chunks_default)}")
        # for i, chunk in enumerate(chunks_default):
        #     print(f"  Chunk {i+1} (zdroj: {chunk.metadata['source']}, start_index: {chunk.metadata.get('start_index')}), délka: {len(chunk.page_content)}")
        #     print(f"    Obsah: {chunk.page_content[:80]}...")
        #     if i > 4 : break # Jen prvních pár
    else:
        print("Nevytvořeny žádné chunky (výchozí parametry).")

    # Test s menší velikostí chunku
    print("\nTest s menší velikostí chunku (chunk_size=200, chunk_overlap=50):")
    chunks_small = split_documents(sample_documents, chunk_size=200, chunk_overlap=50)
    if chunks_small:
        print(f"Celkem vytvořeno chunků: {len(chunks_small)}")
        # for i, chunk in enumerate(chunks_small):
        #     print(f"  Chunk {i+1} (zdroj: {chunk.metadata['source']}, start_index: {chunk.metadata.get('start_index')}), délka: {len(chunk.page_content)}")
        #     print(f"    Obsah: {chunk.page_content[:80]}...")
        #     if i > 4 : break
    else:
        print("Nevytvořeny žádné chunky (malé parametry).")

    # Test s prázdným vstupem
    print("\nTest s prázdným vstupem:")
    chunks_empty = split_documents([])
    if not chunks_empty:
        print("Správně vrácen prázdný seznam pro prázdný vstup.")

    # Načtení reálných dokumentů a jejich rozdělení
    print("\nTest s reálnými dokumenty z data/knowledge_base:")
    # Předpokládáme, že document_loader.py je ve stejném adresáři nebo je Python path správně nastavena
    try:
        from .document_loader import load_documents # Relativní import pro __main__
        real_docs = load_documents() # Načte z data/knowledge_base
        if real_docs:
            print(f"Načteno {len(real_docs)} reálných dokumentů.")
            real_chunks = split_documents(real_docs)
            if real_chunks:
                 print(f"Reálné dokumenty rozděleny na {len(real_chunks)} chunků.")
                 # for i, chunk in enumerate(real_chunks[:5]):
                 #      print(f"  Chunk {i+1} (zdroj: {chunk.metadata['source']}), délka: {len(chunk.page_content)}")
                 #      print(f"    Obsah: {chunk.page_content[:80]}...")
            else:
                print("Reálné dokumenty nebyly rozděleny.")
        else:
            print("Nebyly načteny žádné reálné dokumenty pro test dělení.")
    except ImportError:
        print("Nepodařilo se importovat document_loader pro test s reálnými dokumenty. Spusťte testy jednotlivě.")
    except Exception as e:
        print(f"Chyba při testu s reálnými dokumenty: {e}")
