param (
    [string]$SearchEndpoint,
    [string]$OpenAiEndpoint,
    [string]$EmbeddingModelName,
    [string]$EmbeddingModelApiVersion
)

# Get the folder where this script is located
$scriptRoot = $PSScriptRoot

# Dynamically resolve paths to Python scripts and requirements file
$requirementsPath = Join-Path $scriptRoot "requirements.txt"
$createIndexScript = Join-Path $scriptRoot "index_scripts/01_create_search_index.py"
$processDataScript = Join-Path $scriptRoot "index_scripts/02_process_data.py"

Write-Host $requirementsPath
Write-Host $createIndexScript
Write-Host $processDataScript

# Check for 'python' command
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
}

# Install Python if not found
if (-not $pythonCmd) {
    Write-Host "❌ Python not found. Installing..."
    $pythonInstaller = "python-installer.exe"
    Invoke-WebRequest -Uri "https://www.python.org/ftp/python/3.12.2/python-3.12.2-amd64.exe" -OutFile $pythonInstaller
    Start-Process -FilePath .\$pythonInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
}

# Install dependencies
Start-Process -FilePath $pythonCmd.Source `
    -ArgumentList "-m", "pip", "install", "-r", "`"$requirementsPath`"" `
    -Wait -NoNewWindow

# Set environment variables for Python scripts to consume
$env:SEARCH_ENDPOINT = $SearchEndpoint
$env:OPEN_AI_ENDPOINT_URL = $OpenAiEndpoint
$env:EMBEDDING_MODEL_NAME = $EmbeddingModelName
$env:EMBEDDING_MODEL_API_VERSION = $EmbeddingModelApiVersion

# Run "01_create_search_index.py"
Write-Host "Running $createIndexScript"
Start-Process -FilePath $pythonCmd.Source `
    -ArgumentList "`"$createIndexScript`"" `
    -Wait -NoNewWindow

# Run "02_process_data.py"
Write-Host "Running $processDataScript"
Start-Process -FilePath $pythonCmd.Source `
    -ArgumentList "`"$processDataScript`"" `
    -Wait -NoNewWindow
