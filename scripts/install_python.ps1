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

$cmd = "powershell -ExecutionPolicy Bypass -File process_sample_data.ps1 -SearchEndpoint `"$SearchEndpoint`" -OpenAiEndpoint `"$OpenAiEndpoint`" -EmbeddingModelName `"$EmbeddingModelName`" -EmbeddingModelApiVersion `"$EmbeddingModelApiVersion`""
Write-Host $cmd
Invoke-Expression $cmd
