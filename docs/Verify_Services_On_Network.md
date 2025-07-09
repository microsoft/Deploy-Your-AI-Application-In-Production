# Using a Secure Jump-Box VM to Verify Services on Network

This guide will walk you through using a secure jump-box virtual machine to install the Azure CLI, log in, provide necessary parameters, and execute a testing PowerShell script.

## Steps

### 1. Copy Testing Script to Virtual Machine

Copy [test_azure_resource_conns.ps1](../scripts/test_azure_resource_conns.ps1) to the Virtual Machine.

### 2. Install Azure CLI

While remoted into the Virtual Machine, open a PowerShell window and run the following command to install the Azure CLI:

```powershell
Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -ArgumentList '/I AzureCLI.msi /quiet' -Wait; Remove-Item .\AzureCLI.msi
```

### 3. Log in to Azure

Log in to your Azure account using the following command:

```powershell
az login
```

Follow the instructions to complete the authentication process.

### 4. Provide Parameters

Gather the necessary parameters for your environment from the provisioned resources in the Resource Group. These values can be retrieved from the Azure Portal or in the `.env` file under `/.azure/your-env-name/.env`.

```powershell
$subscriptionId = "your-subscription-id"
$resourceGroup = "your-resource-group-name"
$keyvault = "your-keyvault-name"
$storageAccount = "your-storage-account-name"
$containerRegistry = "your-container-registry-name"
```

### 5. Execute Testing PowerShell Script

```powershell
.\test_azure_resource_conns.ps1 `
    -SubscriptionId $subscriptionId `
    -ResourceGroup $resourceGroup `
    -KeyVault $keyvault `
    -StorageAccount $storageAccount `
    -ContainerRegistry $containerRegistry
```

## Conclusion

By following these steps, you can securely use a jump-box VM to install the Azure CLI, log in, set necessary parameters, and execute a PowerShell script to verify services on your network.