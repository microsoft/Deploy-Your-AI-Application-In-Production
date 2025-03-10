param (
    [Parameter(Mandatory=$true)]
    [string]$subscriptionId,

    [Parameter(Mandatory=$true)]
    [string]$keyvault,

    [Parameter(Mandatory=$true)]
    [string]$storageAccount,

    [Parameter(Mandatory=$true)]
    [string]$resourceGroup,

    [Parameter(Mandatory=$true)]
    [string]$containerRegistry,

    [Parameter(Mandatory=$true)]
    [string]$searchService
)

$greenCheck = @{
    Object = [Char]8730
    ForegroundColor = 'Green'
    NoNewLine = $true
}

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

az login
az account set --subscription $subscriptionId

Write-Host "Testing connection to Key Vault '$keyvault'..." -ForegroundColor Yellow
$secrets = az keyvault secret list --vault-name $keyvault
if ($secrets) {
    Write-Host @greenCheck
    Write-Host " - Successfully retrieved secrets from Key Vault '$keyvault': $secrets" -ForegroundColor Green
} else {
    Write-Error "Error: Not able to retrieve secrets from Key Vault '$keyvault'."
}

Write-Host "Testing connection to Storage Account '$storageAccount'..." -ForegroundColor Yellow
$containerName = az storage container list --account-name $storageAccount --auth-mode login --query "[0].name" --output tsv
if (!$containerName) {
    Write-Error "Error: Not able to retrieve container name from Storage Account '$storageAccount'."
} else {
    $blobs = az storage blob list --account-name $storageAccount --container-name $containerName --auth-mode login
    if ($blobs) {
        Write-Host @greenCheck
        Write-Host " - Successfully retrieved blobs from Storage Account '$storageAccount': $blobs" -ForegroundColor Green
    } else {
        Write-Error "Error: Not able to retrieve blobs from Storage Account '$storageAccount'."
    }
}

Write-Host "Testing connection to Container Registry '$containerRegistry'..." -ForegroundColor Yellow
try {
    $repositories = az acr repository list -n $containerRegistry
    if ($LastExitCode -eq 0) {
        Write-Host @greenCheck
        Write-Host " - Successfully retrieved repositories from Container Registry '$containerRegistry': $repositories" -ForegroundColor Green
    } else {
        Write-Error "Error: Not able to retrieve repositories from Container Registry '$containerRegistry'."
    }
} catch {
    Write-Error "Error: Not able to retrieve repositories from Container Registry '$containerRegistry'."
}

Write-Host "Testing connection to Search Service '$searchService'..." -ForegroundColor Yellow
Write-Host " - Getting access token..."
$accessToken = az account get-access-token --query accessToken -o tsv
if ($accessToken) {

    $headers = @{
        'Authorization' = 'Bearer ' + $accessToken
        'Content-Type' = 'application/json' 
        'Host' = "management.azure.com"
    }
    $url = "https://${searchService}.search.windows.net/indexes?api-version=2024-07-01"
    Invoke-WebRequest -Method GET -Uri $url -Headers $headers | ConvertTo-Json

} else {
    Write-Error "Error: Not able to get access token."
}
