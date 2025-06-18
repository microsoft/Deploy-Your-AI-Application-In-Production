param (
    [string]$SearchEndpoint,
    [string]$OpenAiEndpoint,
    [string]$EmbeddingModelName,
    [string]$EmbeddingModelApiVersion
)

# --- Logging Setup ---
$logDir = "C:\Logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$logFile = "$logDir\process_sample_data.log"
Start-Transcript -Path $logFile -Append

Write-Host "`n===================== Starting Script ====================="

# Get the folder where this script is located
$scriptRoot = $PSScriptRoot

# GitHub repo base path
$baseUrl = "https://raw.githubusercontent.com/microsoft/Deploy-Your-AI-Application-In-Production/data-ingestionscript/scripts/index_scripts"

# Script list
$scripts = @("01_create_search_index.py", "02_process_data.py", "requirements.txt")

# Download all
foreach ($script in $scripts) {
    Write-Host "Downloading the file $script"
    Invoke-WebRequest "$baseUrl/$script" -OutFile $script
}

# Dynamically resolve paths to Python scripts and requirements file
$requirementsPath = Join-Path $scriptRoot "requirements.txt"
$createIndexScript = Join-Path $scriptRoot "01_create_search_index.py"
$processDataScript = Join-Path $scriptRoot "02_process_data.py"

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
$pythonExe = $pythonCmd.Source
Write-Host "✅ Python found at: $pythonExe"

Write-Host $requirementsPath
Write-Host $createIndexScript
Write-Host $processDataScript

# Force refresh PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")

# Try to detect real python path
$pythonExe = Get-Command python | Select-Object -ExpandProperty Source
Write-Host "Using Python command: $pythonExe"

# --- Set Environment Variables ---
$env:SEARCH_ENDPOINT = $SearchEndpoint
$env:OPEN_AI_ENDPOINT_URL = $OpenAiEndpoint
$env:EMBEDDING_MODEL_NAME = $EmbeddingModelName
$env:EMBEDDING_MODEL_API_VERSION = $EmbeddingModelApiVersion

# --- Install Requirements ---
Write-Host "Installing dependencies..."
& $pythonExe -m pip install -r $requirementsPath
if ($LASTEXITCODE -ne 0) {
    Write-Error "pip install failed."
    Stop-Transcript
    exit $LASTEXITCODE
}

# --- Run create_search_index.py ---

Write-Host "running $createIndexScript"
& $pythonExe $createIndexScript
if ($LASTEXITCODE -ne 0) {
    Write-Error "$createIndexScript failed"
    Stop-Transcript
    exit $LASTEXITCODE
}

# --- Run process_data.py ---
Write-Host "Running $processDataScript"
& $pythonExe $processDataScript
if ($LASTEXITCODE -ne 0) {
    Write-Error "$processDataScript failed"
    Stop-Transcript
    exit $LASTEXITCODE
}

Write-Host "All tasks completed successfully."

# --- End Logging ---
Stop-Transcript
