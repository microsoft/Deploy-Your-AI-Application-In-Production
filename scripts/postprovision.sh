 #!/bin/sh

. ./scripts/loadenv.sh

if [ "$AZURE_APP_SAMPLE_ENABLED" = "false" ]; then
    echo "AZURE_APP_SAMPLE_ENABLED is false. Exiting auth_update script."
    exit 1
fi

echo 'Running "auth_update.py"'
./.venv/bin/python ./scripts/auth_update.py --appid "$AZURE_AUTH_APP_ID" --uri "$SAMPLE_APP_URL"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
userName="$AZURE_VM_USERNAME"
virtualMachineId="$AZURE_VM_RESOURCE_ID"

if [ -z "$virtualMachineId" ]; then
  echo "To ingest the sample data locally, follow these steps:"
  echo "1. Open the terminal."
  echo "2. Navigate to the scripts directory: cd $SCRIPT_DIR/scripts"
  echo "3. Run the following command to process the sample data:"
  echo "./process_sample_data.sh '$AZURE_SEARCH_ENDPOINT' '$AZURE_OPENAI_ENDPOINT' '$EMBEDDING_MODEL_NAME' '2025-01-01-preview'"
else
  echo "To ingest the sample data, follow these steps:"
  echo "1. Login to the Virtual Machine using the username '$userName' and Password provided during deployment."
  echo "2. Open the PowerShell terminal."
  echo "3. Navigate to the scripts directory: cd C:\\DataIngestionScripts"
  echo "4. Run the following command to process the sample data:"
  echo "powershell -ExecutionPolicy Bypass -File process_sample_data.ps1 -SearchEndpoint '$AZURE_SEARCH_ENDPOINT' -OpenAiEndpoint '$AZURE_OPENAI_ENDPOINT' -EmbeddingModelName '$EMBEDDING_MODEL_NAME' -EmbeddingModelApiVersion '2025-01-01-preview'"
fi