. ./scripts/loadenv.ps1

$appSampleEnabled = (Get-Content .\.azure\$env:AZURE_ENV_NAME\config.json | ConvertFrom-Json).infra.parameters.appSampleEnabled

# Give preference to AZURE_APP_SAMPLE_ENABLED environment variable
if ($env:AZURE_APP_SAMPLE_ENABLED) {
  $effectiveValue = $env:AZURE_APP_SAMPLE_ENABLED
} else {
  $effectiveValue = $appSampleEnabled
}

$effectiveValue = $effectiveValue.ToString().ToLower()

if (-not $effectiveValue -or $effectiveValue -eq "false" -or $effectiveValue -eq $false) {
  Write-Host "App sample is disabled. Exiting auth_init script."
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
