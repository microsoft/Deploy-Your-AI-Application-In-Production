param (
    [string]$SearchEndpoint,
    [string]$OpenAiEndpoint,
    [string]$EmbeddingModelName,
    [string]$EmbeddingModelApiVersion
)

$pythonZipUrl = "https://www.python.org/ftp/python/3.12.2/python-3.12.2-embed-amd64.zip"
$pythonExtractPath = "C:\Python312"

# Create folder
New-Item -ItemType Directory -Force -Path $pythonExtractPath

# Download zip
$zipPath = "$env:TEMP\python_embed.zip"
Invoke-WebRequest -Uri $pythonZipUrl -OutFile $zipPath

# Extract
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $pythonExtractPath)

# Define Python executable path
$pythonExe = "$pythonExtractPath\python.exe"


# $url = 'https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe'
# $output = "$env:TEMP\\python-installer.exe"
# Invoke-WebRequest -Uri $url -OutFile $output;
# Start-Process -FilePath $output -ArgumentList '/quiet InstallAllUsers=1 PrependPath=1' -Wait;

$cmd = "powershell -ExecutionPolicy Bypass -File process_sample_data.ps1 -SearchEndpoint `"$SearchEndpoint`" -OpenAiEndpoint `"$OpenAiEndpoint`" -EmbeddingModelName `"$EmbeddingModelName`" -EmbeddingModelApiVersion `"$EmbeddingModelApiVersion`""
Write-Host $cmd
Invoke-Expression $cmd
