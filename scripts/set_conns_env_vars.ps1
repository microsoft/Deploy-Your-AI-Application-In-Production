param (
    [Parameter(Mandatory=$false)]
    [string]$tenant,
    
    [Parameter(Mandatory=$false)]
    [string]$subscription,
    
    [Parameter(Mandatory=$false)]
    [string]$resourceGroup,
    
    [Parameter(Mandatory=$false)]
    [string]$foundryProject,

    [Parameter(Mandatory=$false)]
    [switch]$includeVerboseResponseOutputs
)

# Use environment variables as fallback, updated for Foundry Project
if (-not $tenant -and $env:AZURE_ORIGINAL_TENANT_ID) {
    $tenant = $env:AZURE_ORIGINAL_TENANT_ID
    if ($includeVerboseResponseOutputs) {
        Write-Output "Tenant parameter not provided. Using environment variable AZURE_ORIGINAL_TENANT_ID: $tenant"
    }
}

if (-not $subscription -and $env:AZURE_ORIGINAL_SUBSCRIPTION_ID) {
    $subscription = $env:AZURE_ORIGINAL_SUBSCRIPTION_ID
    if ($includeVerboseResponseOutputs) {
        Write-Output "Subscription parameter not provided. Using environment variable AZURE_ORIGINAL_SUBSCRIPTION_ID: $subscription"
    }
}

if (-not $resourceGroup -and $env:AZURE_ORIGINAL_RESOURCE_GROUP) {
    $resourceGroup = $env:AZURE_ORIGINAL_RESOURCE_GROUP
    if ($includeVerboseResponseOutputs) {
        Write-Output "ResourceGroup parameter not provided. Using environment variable AZURE_ORIGINAL_RESOURCE_GROUP: $resourceGroup"
    }
}

if (-not $foundryProject -and $env:AZURE_FOUNDRY_PROJECT_NAME) {
    $foundryProject = $env:AZURE_FOUNDRY_PROJECT_NAME
    if ($includeVerboseResponseOutputs) {
        Write-Output "FoundryProject parameter not provided. Using environment variable AZURE_FOUNDRY_PROJECT_NAME: $foundryProject"
    }
}

if (-not $tenant -or -not $subscription -or -not $resourceGroup -or -not $foundryProject) {
    $response = Read-Host "Start with existing Foundry Project connections? [NOTE: This action cannot be undone after executing. To revert, create a new AZD environment and run the process again.] (yes/no)"
    if ($response -eq "yes") {
        if (-not $tenant) {
            $tenant = Read-Host "Enter Tenant ID"
        }

        if (-not $subscription) {
            $subscription = Read-Host "Enter Subscription ID"
        }

        if (-not $resourceGroup) {
            $resourceGroup = Read-Host "Enter Resource Group"
        }

        if (-not $foundryProject) {
            $foundryProject = Read-Host "Enter Foundry Project Name"
        }

    } elseif ($response -eq "no") {
        Write-Output "Not starting with existing Foundry Project. Exiting script."
        return
    } else {
        Write-Output "Invalid response. Exiting script."
        return
    }
} else {
    Write-Output "All parameters provided. Starting with existing Foundry Project ${foundryProject}."
}

if (-not $tenant -or -not $subscription -or -not $resourceGroup -or -not $foundryProject) {
    throw "Unable to start with existing Foundry Project: One or more required parameters are missing."
}

if (-not (Get-AzContext)) {
    Write-Output "Connecting to Azure account..."
    Connect-AzAccount -Tenant $tenant -SubscriptionId $subscription
}

Set-AzContext -Subscription $subscription

$token = (Get-AzAccessToken).token
# Updated API endpoint for Foundry Project connections
$url = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.MachineLearningServices/workspaces/$foundryProject/connections?api-version=2024-10-01"
$headers = @{   
    'Authorization' = "Bearer $token"
    'Content-Type' = "application/json"
    'Host' = "management.azure.com"
}

$response = Invoke-RestMethod -Method GET -ContentType 'application/json' -Uri $url -Headers $headers
$connections = $response.value

Write-Output "Connections in Foundry Project ${foundryProject}"
Write-Output "----------------------------------"   

Write-Output "Connection count: $($connections.Count)"
if ($connections.Count -eq 0) {
    Write-Output "No connections found in the Foundry Project."
    return
}

if ($includeVerboseResponseOutputs) {
    Write-Output "Connections response:"
    Write-Output $connections
}
Write-Output "----------------------------------"   

$cogServiceAccountsUrl = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/?api-version=2023-05-01"
$cogServiceAccounts = Invoke-RestMethod -Method GET -ContentType 'application/json' -Uri $cogServiceAccountsUrl -Headers $headers

Write-Output "Cognitive Service Accounts in resource group ${resourceGroup}"
Write-Output "----------------------------------"
Write-Output "Cognitive Service Account count: $($cogServiceAccounts.value.Count)"
if ($cogServiceAccounts.value.Count -eq 0) {
    Write-Output "No Cognitive Service Accounts found in the resource group."
    return
}
if ($includeVerboseResponseOutputs) {
    Write-Output "Cognitive Service Accounts response:"
    Write-Output $cogServiceAccounts.value
}
foreach ($account in $cogServiceAccounts.value) {
    $normalizedAccountName = $account.name -replace '[-_]', ''
    Write-Output "Normalized Cognitive Service Account Name: $normalizedAccountName"
}
Write-Output "----------------------------------"

Write-Output "Connections details:"
Write-Output "----------------------------------"
foreach ($connection in $connections) {
    $name = $connection.name
    $authType = $connection.properties.authType
    $category = $connection.properties.category
    $target = $connection.properties.target

    Write-Output "Name: $name"
    Write-Output "AuthType: $authType"
    Write-Output "Category: $category"
    Write-Output "Target: $target"
    
    if ($category -eq "CognitiveSearch") {
        azd env set 'AZURE_AI_SEARCH_ENABLED' 'true'
        Write-Output "Environment variable AZURE_AI_SEARCH_ENABLED set to true"
    }

    if ($category -eq "CognitiveService") {
        foreach ($account in $cogServiceAccounts.value) {
            $normalizedAccountName = $account.name -replace '[-_]', ''
            if ($normalizedAccountName -eq $name) {
                $resourceName = $account.name
                Write-Output "Matched Cognitive Service Account - Connection: '$name' Resource: $resourceName"
                
                switch ($account.kind) {
                    "ContentSafety" {
                        azd env set 'AZURE_AI_CONTENT_SAFETY_ENABLED' 'true'
                        Write-Output "Environment variable AZURE_AI_CONTENT_SAFETY_ENABLED set to true"
                    }
                    "SpeechServices" {
                        azd env set 'AZURE_AI_SPEECH_ENABLED' 'true'
                        Write-Output "Environment variable AZURE_AI_SPEECH_ENABLED set to true"
                    }
                    "FormRecognizer" {
                        azd env set 'AZURE_AI_DOC_INTELLIGENCE_ENABLED' 'true'
                        Write-Output "Environment variable AZURE_AI_DOC_INTELLIGENCE_ENABLED set to true"
                    }
                    "ComputerVision" {
                        azd env set 'AZURE_AI_VISION_ENABLED' 'true'
                        Write-Output "Environment variable AZURE_AI_VISION_ENABLED set to true"
                    }
                    "TextAnalytics" {
                        azd env set 'AZURE_AI_LANGUAGE_ENABLED' 'true'
                        Write-Output "Environment variable AZURE_AI_LANGUAGE_ENABLED set to true"
                    }
                    "TextTranslation" {
                        azd env set 'AZURE_AI_TRANSLATOR_ENABLED' 'true'
                        Write-Output "Environment variable AZURE_AI_TRANSLATOR_ENABLED set to true"
                    }
                    Default {
                        Write-Output "Unknown resource kind: $($account.kind)"
                    }
                }
            }
        }
    }

    Write-Output "-------------------------"
}
Write-Output "----------------------------------"

# Set Foundry Project environment variable for downstream processes
azd env set 'AZURE_FOUNDRY_PROJECT_NAME' $foundryProject
Write-Output "Environment variable AZURE_FOUNDRY_PROJECT_NAME set to $foundryProject"