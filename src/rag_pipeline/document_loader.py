# src/rag_pipeline/document_loader.py
import os
from typing import List
from langchain_community.document_loaders import DirectoryLoader, TextLoader, PyPDFLoader
from langchain_core.documents import Document

# Adresář, kde jsou uloženy dokumenty znalostní báze
# Cesta je relativní ke kořenovému adresáři projektu
DEFAULT_KNOWLEDGE_BASE_DIR = "data/knowledge_base"

def load_documents(directory_path: str = DEFAULT_KNOWLEDGE_BASE_DIR) -> List[Document]:
    """
    Načte dokumenty z určeného adresáře.
    Podporuje .txt a .pdf soubory.

    Args:
        directory_path (str): Cesta k adresáři s dokumenty.

    Returns:
        List[Document]: Seznam načtených dokumentů (objekty LangChain Document).
    """
    if not os.path.isdir(directory_path):
        print(f"Chyba: Adresář '{directory_path}' nebyl nalezen.")
        return []

    # Konfigurace pro DirectoryLoader
    # Načte všechny .txt soubory pomocí TextLoaderu
    # a všechny .pdf soubory pomocí PyPDFLoaderu.
    # Globbing pattern '**/' znamená rekurzivní prohledávání podadresářů.
    loader = DirectoryLoader(
        directory_path,
        glob="**/*.*", # Načte všechny soubory, pak filtrujeme podle typu loaderu
        loader_map={
            ".txt": TextLoader,
            ".pdf": PyPDFLoader, # Vyžaduje `pip install pypdf`
            # Lze přidat další loadery pro .docx, .md atd.
            # ".md": UnstructuredMarkdownLoader,
            # ".docx": UnstructuredWordDocumentLoader,
        },
        show_progress=True,
        use_multithreading=True, # Může zrychlit načítání velkého množství souborů
        silent_errors=True # Potlačí chyby při načítání jednotlivých souborů (např. poškozený PDF)
                           # a pokusí se načíst ostatní.
    )

    try:
        loaded_docs = loader.load()
        print(f"Úspěšně načteno {len(loaded_docs)} dokumentů z '{directory_path}'.")

        # Příklad metadat, která LangChain loadery typicky přidávají:
        # for doc in loaded_docs:
        #     print(f"  Zdroj: {doc.metadata.get('source')}, obsah (část): {doc.page_content[:100]}...")

        return loaded_docs
    except Exception as e:
        print(f"Došlo k chybě při načítání dokumentů z '{directory_path}': {e}")
        return []

if __name__ == '__main__':
    print("Testování načítání dokumentů...")

    # Vytvoření dočasných souborů pro test (pokud nejsou přítomny)
    # V reálném běhu budou soubory v data/knowledge_base
    temp_dir = "temp_kb_test"
    if not os.path.exists(temp_dir):
        os.makedirs(temp_dir)

    with open(os.path.join(temp_dir, "test1.txt"), "w", encoding="utf-8") as f:
        f.write("Toto je první testovací textový dokument.")
    with open(os.path.join(temp_dir, "test2.txt"), "w", encoding="utf-8") as f:
        f.write("Toto je druhý testovací dokument s dalším obsahem.")

    # Pro test PDF by bylo potřeba mít ukázkový PDF soubor a nainstalovaný pypdf
    # Např. vytvořit dummy.pdf v temp_dir
    # try:
    #     from reportlab.pdfgen import canvas
    #     c = canvas.Canvas(os.path.join(temp_dir, "dummy.pdf"))
    #     c.drawString(100, 750, "Toto je testovací PDF dokument.")
    #     c.save()
    #     print("Vytvořen dummy.pdf pro testování.")
    # except ImportError:
    #     print("Knihovna reportlab není nainstalována, PDF test bude přeskočen.")
    #     pass


    documents = load_documents(temp_dir)

    if documents:
        print(f"\nCelkem načteno dokumentů: {len(documents)}")
        for i, doc in enumerate(documents):
            print(f"\nDokument {i+1}:")
            print(f"  Zdroj: {doc.metadata.get('source')}")
            # print(f"  Obsah: {doc.page_content}") # Může být dlouhé
            print(f"  Obsah (prvních 50 znaků): {doc.page_content[:50]}...")
    else:
        print("Nebyly načteny žádné dokumenty.")

    # Úklid dočasných souborů
    import shutil
    if os.path.exists(temp_dir):
        try:
            shutil.rmtree(temp_dir)
            print(f"\nDočasný adresář '{temp_dir}' byl smazán.")
        except Exception as e:
            print(f"Chyba při mazání dočasného adresáře '{temp_dir}': {e}")

    print("\nTestování s výchozím adresářem (data/knowledge_base):")
    # Tento test předpokládá, že soubory smernice_crp.txt a smernice_psa.txt existují
    # v data/knowledge_base
    kb_documents = load_documents() # Použije DEFAULT_KNOWLEDGE_BASE_DIR
    if kb_documents:
        print(f"\nCelkem načteno dokumentů z KB: {len(kb_documents)}")
        for doc in kb_documents:
            print(f"  Zdroj z KB: {doc.metadata.get('source')}, obsah (část): {doc.page_content[:50]}...")
    else:
        print("Nebyly načteny žádné dokumenty z výchozího KB adresáře.")
