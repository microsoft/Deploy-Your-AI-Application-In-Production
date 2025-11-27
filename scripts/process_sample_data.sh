#!/bin/bash

set -e  # Exit immediately if a command fails
set -o pipefail

# --- Input Parameters ---
SearchEndpoint="$1"
OpenAiEndpoint="$2"
ProjectEndpoint="$3"
EmbeddingModelName="$4"
EmbeddingModelApiVersion="$5"

if [ $# -ne 5 ]; then
  echo "Usage: $0 <SearchEndpoint> <OpenAiEndpoint> <ProjectEndpoint> <EmbeddingModelName> <EmbeddingModelApiVersion>"
  exit 1
fi

# --- Resolve script and working directories ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
SCRIPT_ROOT="$SCRIPT_DIR/index_scripts"
PYTHON_EXTRACT_PATH="$SCRIPT_DIR/../.venv/bin"
PYTHON_EXE="$PYTHON_EXTRACT_PATH/python"

# --- Create logs directory if not exists ---
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/process_sample_data.log"

# --- Start Logging ---
echo -e "\n===================== Starting Script =====================" | tee -a "$LOG_FILE"

# --- Python Executable Check ---
echo "✅ Python expected at: $PYTHON_EXE" | tee -a "$LOG_FILE"

# --- Define script and requirements paths ---
REQUIREMENTS_PATH="$SCRIPT_ROOT/requirements.txt"
CREATE_INDEX_SCRIPT="$SCRIPT_ROOT/01_create_search_index.py"
PROCESS_DATA_SCRIPT="$SCRIPT_ROOT/02_process_data.py"

echo "Using Python command: $PYTHON_EXE" | tee -a "$LOG_FILE"
echo "$REQUIREMENTS_PATH" | tee -a "$LOG_FILE"
echo "$CREATE_INDEX_SCRIPT" | tee -a "$LOG_FILE"
echo "$PROCESS_DATA_SCRIPT" | tee -a "$LOG_FILE"

# --- Export environment variables ---
export SEARCH_ENDPOINT="$SearchEndpoint"
export OPEN_AI_ENDPOINT_URL="$OpenAiEndpoint"
export AZURE_AI_AGENT_ENDPOINT="$ProjectEndpoint"
export EMBEDDING_MODEL_NAME="$EmbeddingModelName"
export EMBEDDING_MODEL_API_VERSION="$EmbeddingModelApiVersion"
export USE_LOCAL_FILES="true"

# --- Install Requirements ---
echo "Installing dependencies..." | tee -a "$LOG_FILE"
"$PYTHON_EXE" -m pip install -r "$REQUIREMENTS_PATH" 2>&1 | tee -a "$LOG_FILE"

# --- Run create_search_index.py ---
echo "Running $CREATE_INDEX_SCRIPT" | tee -a "$LOG_FILE"
"$PYTHON_EXE" "$CREATE_INDEX_SCRIPT" 2>&1 | tee -a "$LOG_FILE"

# --- Run process_data.py ---
echo "Running $PROCESS_DATA_SCRIPT" | tee -a "$LOG_FILE"
"$PYTHON_EXE" "$PROCESS_DATA_SCRIPT" 2>&1 | tee -a "$LOG_FILE"

echo "✅ All tasks completed successfully." | tee -a "$LOG_FILE"
