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
