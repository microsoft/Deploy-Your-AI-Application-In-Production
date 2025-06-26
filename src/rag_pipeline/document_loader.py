# src/rag_pipeline/document_loader.py
import os
from typing import List
from langchain_community.document_loaders import DirectoryLoader, TextLoader, PyPDFLoader
from langchain_core.documents import Document

def load_documents_from_directory(directory_path: str) -> List[Document]:
    """
    Načte dokumenty z daného adresáře.
    Podporuje .txt a .pdf soubory.

    Args:
        directory_path: Cesta k adresáři s dokumenty.

    Returns:
        Seznam načtených LangChain dokumentů.
    """
    if not os.path.isdir(directory_path):
        raise ValueError(f"Adresář nebyl nalezen: {directory_path}")

    # Konfigurace pro TextLoader pro explicitní UTF-8 kódování
    # Glob pattern pro TextLoader by měl být specifický, aby se nenačítaly PDFka jako text.
    # Proto použijeme dva separátní loadery a zkombinujeme výsledky.

    print(f"Načítání dokumentů z adresáře: {directory_path}")

    loaded_documents: List[Document] = []

    # Načtení .txt souborů
    try:
        txt_loader = DirectoryLoader(
            directory_path,
            glob="**/*.txt",
            loader_cls=TextLoader,
            loader_kwargs={"encoding": "utf-8"},
            show_progress=True,
            use_multithreading=True, # Může zrychlit načítání více souborů
            silent_errors=True # Ignoruje soubory, které nelze načíst
        )
        txt_documents = txt_loader.load()
        if txt_documents:
            loaded_documents.extend(txt_documents)
            print(f"Načteno {len(txt_documents)} textových souborů.")
    except Exception as e:
        print(f"Chyba při načítání TXT souborů: {e}")


    # Načtení .pdf souborů
    try:
        pdf_loader = DirectoryLoader(
            directory_path,
            glob="**/*.pdf",
            loader_cls=PyPDFLoader,
            show_progress=True,
            use_multithreading=True,
            silent_errors=True
        )
        pdf_documents = pdf_loader.load()
        if pdf_documents:
            loaded_documents.extend(pdf_documents)
            print(f"Načteno {len(pdf_documents)} PDF souborů.")
    except Exception as e:
        # PyPDFLoader může mít více závislostí, např. pypdf.
        # Pokud by chyběly, zde by se to projevilo.
        print(f"Chyba při načítání PDF souborů: {e}. Ujistěte se, že máte nainstalovanou knihovnu 'pypdf'.")

    if not loaded_documents:
        print("Nebyly nalezeny žádné podporované dokumenty (.txt, .pdf) k načtení.")
    else:
        print(f"Celkem načteno {len(loaded_documents)} dokumentů.")
        # Příklad metadat prvního dokumentu
        # if loaded_documents:
        #     print("Příklad metadat prvního dokumentu:")
        #     print(loaded_documents[0].metadata)

    return loaded_documents

if __name__ == '__main__':
    # Příklad použití - cesta relativní k rootu projektu, pokud spouštíme odtud
    # Pokud spouštíme tento soubor přímo, cesta musí být relativní k tomuto souboru
    # nebo absolutní.

    # Získání cesty k adresáři 'data/knowledge_base' relativně k tomuto skriptu
    current_script_path = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.abspath(os.path.join(current_script_path, "..", ".."))
    kb_path = os.path.join(project_root, "data", "knowledge_base")

    print(f"Očekávaná cesta ke znalostní bázi: {kb_path}")

    if not os.path.exists(kb_path):
        print(f"CHYBA: Adresář znalostní báze '{kb_path}' neexistuje. Vytvořte ho a vložte do něj ukázkové soubory.")
    else:
        # Testovací PDF soubor (můžete si vytvořit prázdný test.pdf v data/knowledge_base)
        # with open(os.path.join(kb_path, "test.pdf"), "w") as f:
        #     f.write("%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Count 1/Kids[3 0 R]>>endobj 3 0 obj<</Type/Page/MediaBox[0 0 612 792]>>endobj xref\n0 4\n0000000000 65535 f\n0000000010 00000 n\n0000000059 00000 n\n0000000103 00000 n\ntrailer<</Size 4/Root 1 0 R>>\nstartxref\n128\n%%EOF")

        documents = load_documents_from_directory(kb_path)
        if documents:
            print(f"\nNačteno celkem {len(documents)} dokumentů.")
            # print("Obsah prvního dokumentu (prvních 200 znaků):")
            # print(documents[0].page_content[:200])
            # print("Metadata prvního dokumentu:")
            # print(documents[0].metadata)
        else:
            print("Nebyly načteny žádné dokumenty.")

    # Test s neexistujícím adresářem
    try:
        load_documents_from_directory("neexistujici_adresar_test")
    except ValueError as e:
        print(f"Očekávaná chyba: {e}")
