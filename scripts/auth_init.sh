#!/bin/bash

# Load environment variables from a shell script
. ./scripts/loadenv.sh

# Check if AZURE_APP_SAMPLE_ENABLED is not set or is "false"
if [[ -z "$AZURE_APP_SAMPLE_ENABLED" || "$AZURE_APP_SAMPLE_ENABLED" == "false" ]]; then
  echo "AZURE_APP_SAMPLE_ENABLED is false. Exiting auth_init script."
  exit 0
fi

echo 'Running "auth_init.py"'
./.venv/bin/python ./scripts/auth_init.py --appid "$AZURE_AUTH_APP_ID"
