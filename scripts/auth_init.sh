#!/bin/bash

# Load environment variables from a shell script
. ./scripts/loadenv.sh

appSampleEnabled=$(./.venv/bin/python -c "import json; print(str(json.load(open('.azure/$AZURE_ENV_NAME/config.json'))['infra']['parameters']['appSampleEnabled']).lower())" 2>/dev/null || echo "false")

# Give preference to AZURE_APP_SAMPLE_ENABLED environment variable
if [[ -n "$AZURE_APP_SAMPLE_ENABLED" ]]; then
  effectiveValue="${AZURE_APP_SAMPLE_ENABLED}"
else
  effectiveValue="$appSampleEnabled"
fi

effectiveValue=$(echo "$effectiveValue" | tr '[:upper:]' '[:lower:]')

if [[ -z "$effectiveValue" || "$effectiveValue" == "false" ]]; then
  echo "App sample is disabled. Exiting auth_init script."
  exit 0
fi

echo 'Running "auth_init.py"'
./.venv/bin/python ./scripts/auth_init.py --appid "$AZURE_AUTH_APP_ID"
