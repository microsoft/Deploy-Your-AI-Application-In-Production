param (
    [string]$SearchEndpoint,
    [string]$OpenAiEndpoint,
    [string]$EmbeddingModelName,
    [string]$EmbeddingModelApiVersion
)

$url = 'https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe'
$output = "$env:TEMP\\python-installer.exe"
Invoke-WebRequest -Uri $url -OutFile $output;
Start-Process -FilePath $output -ArgumentList '/quiet InstallAllUsers=1 PrependPath=1' -Wait;

$baseUrl = "https://raw.githubusercontent.com/microsoft/Deploy-Your-AI-Application-In-Production/data-ingestionscript/scripts/"

# Script list
$scripts = @("process_sample_data.ps1")
$outputPath = "C:\DataIngestionScripts"

# Ensure the output directory exists
if (!(Test-Path -Path $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
}

# Download all
foreach ($script in $scripts) {
    $destination = Join-Path $outputPath $script
    Write-Host "Downloading the file $script to $destination"
    Invoke-WebRequest "$baseUrl/$script" -OutFile $destination
}