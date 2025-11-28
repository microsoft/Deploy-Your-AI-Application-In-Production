from azure.identity import DefaultAzureCredential
from azure.ai.inference import EmbeddingsClient
from urllib.parse import urlparse
import re
import time
from pypdf import PdfReader
from io import BytesIO
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
import os
import requests

search_endpoint = os.getenv("SEARCH_ENDPOINT")
ai_project_endpoint = os.getenv("AZURE_AI_AGENT_ENDPOINT")  # AI Foundry Project endpoint
embedding_model_name = os.getenv("EMBEDDING_MODEL_NAME")
embedding_model_api_version = os.getenv("EMBEDDING_MODEL_API_VERSION")
use_local_files = (os.getenv("USE_LOCAL_FILES") == "true")
index_name = "ai_app_index"

print(f"Creating search index at {search_endpoint} with index name {index_name}")
print(f"Using AI Foundry Project endpoint: {ai_project_endpoint}")
print(f"Using embedding model: {embedding_model_name} with API version: {embedding_model_api_version}")

# Function: Get Embeddings using Azure AI Inference SDK with Foundry endpoint
def get_embeddings(text: str, ai_project_endpoint: str, embedding_model_api_version: str):
    credential = DefaultAzureCredential()
    
    # Construct inference endpoint with /models path for Azure AI Foundry
    inference_endpoint = f"https://{urlparse(ai_project_endpoint).netloc}/models"
    
    # Create embeddings client using Azure AI Inference SDK
    embeddings_client = EmbeddingsClient(
        endpoint=inference_endpoint,
        credential=credential,
        credential_scopes=["https://cognitiveservices.azure.com/.default"]
    )
    
    # Create embeddings using the model name from environment
    response = embeddings_client.embed(
        model=embedding_model_name,
        input=[text]
    )
    
    embedding = response.data[0].embedding
    return embedding

# Function: Clean Spaces with Regex -
def clean_spaces_with_regex(text):
    # Use a regular expression to replace multiple spaces with a single space
    cleaned_text = re.sub(r'\s+', ' ', text)
    # Use a regular expression to replace consecutive dots with a single dot
    cleaned_text = re.sub(r'\.{2,}', '.', cleaned_text)
    return cleaned_text


def chunk_data(text):
    tokens_per_chunk = 256  # 1024 # 500
    text = clean_spaces_with_regex(text)

    sentences = text.split('. ')  # Split text into sentences
    chunks = []
    current_chunk = ''
    current_chunk_token_count = 0

    # Iterate through each sentence
    for sentence in sentences:
        # Split sentence into tokens
        tokens = sentence.split()

        # Check if adding the current sentence exceeds tokens_per_chunk
        if current_chunk_token_count + len(tokens) <= tokens_per_chunk:
            # Add the sentence to the current chunk
            if current_chunk:
                current_chunk += '. ' + sentence
            else:
                current_chunk += sentence
            current_chunk_token_count += len(tokens)
        else:
            # Add current chunk to chunks list and start a new chunk
            chunks.append(current_chunk)
            current_chunk = sentence
            current_chunk_token_count = len(tokens)

    # Add the last chunk
    if current_chunk:
        chunks.append(current_chunk)

    return chunks

search_credential = DefaultAzureCredential()

search_client = SearchClient(search_endpoint, index_name, search_credential)
index_client = SearchIndexClient(endpoint=search_endpoint, credential=search_credential)


def prepare_search_doc(content, document_id, filename):
    chunks = chunk_data(content)
    results = []
    chunk_num = 0
    for chunk in chunks:
        chunk_num += 1
        chunk_id = document_id + '_' + str(chunk_num).zfill(2)

        try:
            v_contentVector = get_embeddings(str(chunk), ai_project_endpoint, embedding_model_api_version)
        except Exception as e:
            print(f"Error occurred: {e}. Retrying after 30 seconds...")
            time.sleep(30)
            try:
                v_contentVector = get_embeddings(str(chunk), ai_project_endpoint, embedding_model_api_version)
            except Exception as e:
                print(f"Retry failed: {e}. Setting v_contentVector to an empty list.")
                v_contentVector = []

        result = {
            "id": chunk_id,
            "chunk_id": chunk_id,
            "content": chunk,
            # "sourceurl": path.name.split('/')[-1],
            "sourceurl": filename,
            "contentVector": v_contentVector
        }
        results.append(result)
    return results

def extract_text_from_pdf(reader, file_name):
    document_id = file_name.split('_')[1].replace('.pdf', '') if '_' in file_name else file_name.replace('.pdf', '')
    text = ''
    for page in reader.pages:
        text += page.extract_text()
    return prepare_search_doc(text, document_id, file_name)

def load_pdfs_from_local(path):
    local_docs = []
    print("Loading files from local folder...")
    pdf_files = [f for f in os.listdir(path) if f.endswith(".pdf")]

    for file_name in pdf_files:
        file_path = os.path.join(path, file_name)
        print(f" Processing: {file_name}")
        with open(file_path, "rb") as f:
            pdf_reader = PdfReader(f)
            result = extract_text_from_pdf(pdf_reader, file_name)
            local_docs.extend(result)
    return local_docs


def load_pdfs_from_github():
    github_docs = []

    # === CONFIG ===
    owner = "microsoft"
    repo = "Deploy-Your-AI-Application-In-Production"
    path = "data"
    branch = "main"
    headers = {
        "Cache-Control": "no-cache",
        "User-Agent": "Mozilla/5.0"
    }
    
    print("Downloading files from GitHub...")
    api_url = f"https://api.github.com/repos/{owner}/{repo}/contents/{path}?ref={branch}"
    response = requests.get(api_url, headers=headers)
    response.raise_for_status()

    files = response.json()
    pdf_files = [f for f in files if f["name"].endswith(".pdf")]

    for file in pdf_files:
        raw_url = file["download_url"]
        file_name = file["name"]
        print(f" Processing: {file_name}")
        print(f" Downloading from: {raw_url}")
        pdf_resp = requests.get(raw_url, headers=headers)
        pdf_resp.raise_for_status()
        pdf_reader = PdfReader(BytesIO(pdf_resp.content))
        result = extract_text_from_pdf(pdf_reader, file_name)
        github_docs.extend(result)
    return github_docs

# === MAIN ===
local_data_path = "../data"

docs = load_pdfs_from_local(local_data_path) if use_local_files else load_pdfs_from_github()

if docs:
    results = search_client.upload_documents(documents=docs)

print("Finished processing file(s).")
