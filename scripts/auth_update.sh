 #!/bin/sh

. ./scripts/loadenv.sh

if [ "$AZURE_APP_SAMPLE_ENABLED" = "false" ]; then
    echo "AZURE_APP_SAMPLE_ENABLED is false. Exiting auth_update script."
    exit 1
fi

echo 'Running "auth_update.py"'
./.venv/bin/python ./scripts/auth_update.py --appid "$AZURE_AUTH_APP_ID" --uri "$SAMPLE_APP_URL"
