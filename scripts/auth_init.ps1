. ./scripts/loadenv.ps1

if (-not $env:AZURE_APP_SAMPLE_ENABLED -or $env:AZURE_APP_SAMPLE_ENABLED -eq "false") {
  Write-Host "AZURE_APP_SAMPLE_ENABLED is false. Exiting auth_init script."
  exit
}

$venvPythonPath = "./.venv/scripts/python.exe"
if (Test-Path -Path "/usr") {
  # fallback to Linux venv path
  $venvPythonPath = "./.venv/bin/python"
}

Write-Host 'Running "auth_init.py"'
$appId = $env:AZURE_AUTH_APP_ID ?? "no-id"
Start-Process -FilePath $venvPythonPath -ArgumentList "./scripts/auth_init.py --appid $appId" -Wait -NoNewWindow
