param (
    [Parameter(Mandatory=$false)]
    [string]$tenant,
    
    [Parameter(Mandatory=$false)]
    [string]$subscription,
    
    [Parameter(Mandatory=$false)]
    [string]$resourceGroup,
    
    [Parameter(Mandatory=$false)]
    [string]$workspace,

    [Parameter(Mandatory=$false)]
    [switch]$includeVerboseResponseOutputs
)

if (-not $PSBoundParameters.ContainsKey('tenant') -or 
    -not $PSBoundParameters.ContainsKey('subscription') -or 
    -not $PSBoundParameters.ContainsKey('resourceGroup') -or 
    -not $PSBoundParameters.ContainsKey('workspace')) {
    Write-Output "All parameters (tenant, subscription, resourceGroup, workspace) must be supplied."
    exit
}

if (-not (Get-AzContext)) {
    Write-Output "Connecting to Azure account..."
    Connect-AzAccount -Tenant $tenant -SubscriptionId $subscription
}

Set-AzContext -Subscription $subscription

$token = (Get-AzAccessToken).token
$url = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.MachineLearningServices/workspaces/$workspace/connections?api-version=2024-10-01"
$headers = @{   
    'Authorization' = "Bearer $token"
    'Content-Type' = "application/json"
    'Host' = "management.azure.com"
}

$response = Invoke-RestMethod -Method GET -ContentType 'application/json' -Uri $url -Headers $headers
$connections = $response.value

Write-Output "Connections in workspace ${workspace}"
Write-Output "----------------------------------"   

Write-Output "Connection count: $($connections.Count)"
if ($connections.Count -eq 0) {
    Write-Output "No connections found in the workspace."
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
        $env:AZURE_AI_SEARCH_ENABLED = "true"
        Write-Output "Environment variable AZURE_AI_SEARCH_ENABLED set to true"
    }

    if ($category -eq "CognitiveService") {
        foreach ($account in $cogServiceAccounts.value) {
            $normalizedAccountName = $account.name -replace '[-_]', ''
            if ($normalizedAccountName -eq $name) {
                $resourceName = $account.name
                Write-Output "Matched Cognitive Service Account - Connection: '$name' Resource: $resourceName"

                $resourceUrl = "https://management.azure.com/subscriptions/$subscription/resourceGroups/$resourceGroup/providers/Microsoft.CognitiveServices/accounts/$resourceName/?api-version=2023-05-01"
                $resourceResponse = Invoke-RestMethod -Method GET -ContentType 'application/json' -Uri $resourceUrl -Headers $headers
        
                if ($resourceResponse -ne $null) {
                    if ($includeVerboseResponseOutputs) {
                        Write-Output "Resource details for ${resourceName}:"
                        Write-Output $resourceResponse
                    }

                    switch ($resourceResponse.kind) {
                        "ContentSafety" {
                            $env:AZURE_AI_CONTENT_SAFETY_ENABLED = "true"
                            Write-Output "Environment variable AZURE_AI_CONTENT_SAFETY_ENABLED set to true"
                        }
                        "SpeechServices" {
                            $env:AZURE_AI_SPEECH_ENABLED = "true"
                            Write-Output "Environment variable AZURE_AI_SPEECH_ENABLED set to true"
                        }
                        "FormRecognizer" {
                            $env:AZURE_AI_DOC_INTELLIGENCE_ENABLED = "true"
                            Write-Output "Environment variable AZURE_AI_DOC_INTELLIGENCE_ENABLED set to true"
                        }
                        "ComputerVision" {
                            $env:AZURE_AI_VISION_ENABLED = "true"
                            Write-Output "Environment variable AZURE_AI_VISION_ENABLED set to true"
                        }
                        "TextAnalytics" {
                            $env:AZURE_AI_LANGUAGE_ENABLED = "true"
                            Write-Output "Environment variable AZURE_AI_LANGUAGE_ENABLED set to true"
                        }
                        "TextTranslation" {
                            $env:AZURE_AI_TRANSLATOR_ENABLED = "true"
                            Write-Output "Environment variable AZURE_AI_TRANSLATOR_ENABLED set to true"
                        }
                        Default {
                            Write-Output "Unknown resource kind: $($resourceResponse.kind)"
                        }
                    }
                } else {
                    Write-Output "Resource $resourceName not found in resource group $resourceGroup."
                }

                break;
            }
        }
    }

    if ($category -eq "ApiKey" -and $target -eq "https://api.bing.microsoft.com/") {
        $env:AZURE_AI_BING_GROUNDING_ENABLED = "true"
        Write-Output "Environment variable AZURE_AI_BING_GROUNDING_ENABLED set to true"
    }

    Write-Output "-------------------------"
}
Write-Output "----------------------------------"
