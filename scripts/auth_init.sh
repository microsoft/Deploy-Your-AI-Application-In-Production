 #!/bin/sh

. ./scripts/loadenv.sh

if [ "$AZURE_APP_SAMPLE_ENABLED" = "false" ]; then
    echo "AZURE_APP_SAMPLE_ENABLED is false. Exiting auth_init script."
    exit 1
fi

echo 'Running "auth_init.py"'
./.venv/bin/python ./scripts/auth_init.py --appid "$AZURE_AUTH_APP_ID"
