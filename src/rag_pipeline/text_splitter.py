# src/rag_pipeline/text_splitter.py
from typing import List
from langchain_core.documents import Document
from langchain.text_splitter import RecursiveCharacterTextSplitter

def split_documents(
    documents: List[Document],
    chunk_size: int = 1000,
    chunk_overlap: int = 200
) -> List[Document]:
    """
    Rozdělí seznam LangChain dokumentů na menší části (chunky).

    Args:
        documents: Seznam dokumentů k rozdělení.
        chunk_size: Maximální velikost jednoho chunku (v počtu znaků).
        chunk_overlap: Počet znaků překryvu mezi sousedními chunky.

    Returns:
        Seznam rozdělených dokumentů (chunků).
    """
    if not documents:
        print("Nebyly poskytnuty žádné dokumenty k rozdělení.")
        return []

    print(f"Rozdělování {len(documents)} dokumentů na chunky...")
    print(f"Nastavení splitteru: chunk_size={chunk_size}, chunk_overlap={chunk_overlap}")

    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        length_function=len,
        # add_start_index=True, # Může být užitečné pro odkazování na původní pozici
    )

    split_docs = text_splitter.split_documents(documents)

    print(f"Počet dokumentů před rozdělením: {len(documents)}")
    print(f"Počet dokumentů (chunků) po rozdělení: {len(split_docs)}")

    # Příklad metadat a obsahu prvního chunku
    # if split_docs:
    #     print("\nPříklad prvního chunku:")
    #     print(f"Obsah (prvních 100 znaků): {split_docs[0].page_content[:100]}")
    #     print(f"Metadata: {split_docs[0].metadata}")

    return split_docs

if __name__ == '__main__':
    # Příklad použití
    # Nejprve potřebujeme načíst nějaké dokumenty
    from document_loader import load_documents_from_directory
    import os

    current_script_path = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(current_script_path, "..", ".."))
    kb_path = os.path.join(project_root, "data", "knowledge_base")

    if not os.path.exists(kb_path):
        print(f"CHYBA: Adresář znalostní báze '{kb_path}' neexistuje pro testování text_splitter.")
    else:
        raw_documents = load_documents_from_directory(kb_path)
        if raw_documents:
            chunks = split_documents(raw_documents, chunk_size=500, chunk_overlap=100)

            if chunks:
                print(f"\nCelkem vytvořeno {len(chunks)} chunků.")
                # Zobrazení detailů několika prvních chunků pro kontrolu
                for i, chunk in enumerate(chunks[:3]): # Zobrazíme první 3 chunky
                    print(f"\n--- Chunk {i+1} ---")
                    print(f"Zdroj: {chunk.metadata.get('source', 'N/A')}")
                    # print(f"Start index (pokud add_start_index=True): {chunk.metadata.get('start_index', 'N/A')}")
                    print(f"Délka obsahu: {len(chunk.page_content)}")
                    print(f"Obsah (prvních 150 znaků): '{chunk.page_content[:150]}...'")
            else:
                print("Nebyly vytvořeny žádné chunky.")
        else:
            print("Nebyly načteny žádné dokumenty pro testování text_splitter.")

    # Test s prázdným seznamem dokumentů
    print("\nTest s prázdným seznamem dokumentů:")
    empty_chunks = split_documents([])
    print(f"Počet chunků z prázdného vstupu: {len(empty_chunks)}")
