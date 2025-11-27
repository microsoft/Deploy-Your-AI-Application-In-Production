. ./scripts/loadenv.ps1

if (-not $env:AZURE_APP_SAMPLE_ENABLED -or $env:AZURE_APP_SAMPLE_ENABLED -eq "false") {
  Write-Host "AZURE_APP_SAMPLE_ENABLED is false. Exiting auth_update script."
  exit
}

$venvPythonPath = "./.venv/scripts/python.exe"
if (Test-Path -Path "/usr") {
  # fallback to Linux venv path
  $venvPythonPath = "./.venv/bin/python"
}

Write-Host 'Running "auth_update.py"'
Start-Process -FilePath $venvPythonPath -ArgumentList "./scripts/auth_update.py --appid $env:AZURE_AUTH_APP_ID --uri $env:SAMPLE_APP_URL" -Wait -NoNewWindow

$userName = $env:AZURE_VM_USERNAME
$virtualMachineId = $env:AZURE_VM_RESOURCE_ID
if (-not $virtualMachineId) {
    Write-Host "To ingest the sample data locally, follow these steps:"
    Write-Host "1. Open the PowerShell terminal."
    Write-Host "2. Navigate to the scripts directory: cd $PSScriptRoot"
    Write-Host "3. Run the below commands to process & ingest the sample data:"
    Write-Host "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
    Write-Host ".\process_sample_data.ps1 -SearchEndpoint '$env:AZURE_SEARCH_ENDPOINT' -OpenAiEndpoint '$env:AZURE_OPENAI_ENDPOINT' -ProjectEndpoint '$env:AZURE_AI_AGENT_ENDPOINT' -EmbeddingModelName '$env:EMBEDDING_MODEL_NAME' -EmbeddingModelApiVersion '2025-01-01-preview' -UseLocalFiles `$true"
} else {
    Write-Host "To ingest the sample data, follow these steps:"
    Write-Host "1. Login to the Virtual Machine using the username '$userName' and Password provided during deployment."
    Write-Host "2. Open the PowerShell terminal."
    Write-Host "3. Navigate to the scripts directory: cd C:\DataIngestionScripts"
    Write-Host "4. Run the following commands to process & ingest the sample data:"
    Write-Host "powershell -ExecutionPolicy Bypass -File process_sample_data.ps1 -SearchEndpoint '$env:AZURE_SEARCH_ENDPOINT' -OpenAiEndpoint '$env:AZURE_OPENAI_ENDPOINT' -ProjectEndpoint '$env:AZURE_AI_AGENT_ENDPOINT' -EmbeddingModelName '$env:EMBEDDING_MODEL_NAME' -EmbeddingModelApiVersion '2025-01-01-preview'"
}