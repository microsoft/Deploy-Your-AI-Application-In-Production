# Bicep Parameters - Modern vs Legacy Formats

This repository now supports **both** parameter file formats:

## ✅ Recommended: `.bicepparam` (Modern)

**File**: `infra/main.bicepparam`

### Benefits:
- ✅ **Type-safe** - Compile-time validation against Bicep template
- ✅ **IntelliSense** - Full autocomplete and inline documentation  
- ✅ **Better syntax** - Native Bicep syntax instead of JSON
- ✅ **Comments** - Inline documentation for all parameters
- ✅ **Validation** - Catches errors before deployment

### Usage with azd:
```bash
azd up
# or
azd provision
```

azd automatically detects and uses `.bicepparam` files when present.

### Direct deployment:
```bash
az deployment group create \
  --resource-group <rg-name> \
  --parameters infra/main.bicepparam
```

---

## Legacy: `.json` (Still Supported)

**File**: `infra/main.parameters.json`

### When to use:
- Working with older azd versions
- CI/CD pipelines that expect JSON
- Team preference for JSON format

### Usage:
```bash
az deployment group create \
  --resource-group <rg-name> \
  --template-file infra/main.bicep \
  --parameters infra/main.parameters.json
```

---

## Key Differences

### Bicepparam Example:
```bicep
using './main.bicep'

param location = readEnvironmentVariable('AZURE_LOCATION', 'eastus2')

param deployToggles = {
  logAnalytics: true
  appInsights: true
  // ... more toggles
}
```

### JSON Example:
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "parameters": {
    "location": {
      "value": "${AZURE_LOCATION=eastus2}"
    },
    "deployToggles": {
      "value": {
        "logAnalytics": true,
        "appInsights": true
      }
    }
  }
}
```

---

## Our Recommendation

**Use `.bicepparam`** for new projects and when editing parameters:

1. **Better developer experience** with IntelliSense
2. **Catch errors early** before deployment
3. **Modern tooling support** in VS Code
4. **Inline documentation** shows what each parameter does

The `.json` file is kept for backward compatibility but will eventually be deprecated.

---

## Migration

To migrate from JSON to bicepparam:

1. Open `infra/main.bicepparam`
2. Copy any custom values from `infra/main.parameters.json`
3. Update the bicepparam file (IntelliSense will guide you)
4. Test with `azd provision --what-if`

---

## More Information

- [Bicep Parameter Files Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/parameter-files)
- [Azure Developer CLI Documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)
