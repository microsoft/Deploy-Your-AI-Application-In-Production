# Bicep Conditional Output Pattern

## The Problem

When using conditional module deployment in Bicep, you cannot directly use ternary operators in outputs that reference conditional modules:

```bicep
// ❌ THIS FAILS with "module | null may be null" error
module myModule './module.bicep' = if (condition) {
  // ...
}

output moduleId string = condition ? myModule!.outputs.resourceId : ''
```

**Error:** `An expression of type 'module | null' cannot be assigned to a type 'string'`

## The Solution: Intermediate Variables

The AI Landing Zone pattern uses intermediate variables to resolve module outputs BEFORE they're used in output declarations:

```bicep
// ✅ THIS WORKS - AI Landing Zone Pattern
module myModule './module.bicep' = if (condition) {
  // ...
}

// Variable resolves the conditional module output
var moduleId = condition ? myModule!.outputs.resourceId : ''

// Output simply references the variable
output moduleId string = moduleId
```

## Why This Works

1. **Variables can use conditional expressions**: Bicep allows variables to use ternary operators with the `!` (non-null assertion) operator
2. **Outputs are simple references**: The output declaration just references the variable value (no conditional logic)
3. **Type safety**: The variable's type is resolved at declaration, not at output

## Complete Example

```bicep
// ===========================================
// PARAMETERS
// ===========================================

@description('Deployment toggles')
param deployToggles object = {
  storage: true
  keyVault: false
}

// ===========================================
// MODULES - Conditional Deployment
// ===========================================

module storageAccount './storage.bicep' = if (deployToggles.storage) {
  name: 'storage-deployment'
  params: {
    name: 'mystorageaccount'
  }
}

module keyVault './keyvault.bicep' = if (deployToggles.keyVault) {
  name: 'keyvault-deployment'
  params: {
    name: 'mykeyvault'
  }
}

// ===========================================
// VARIABLES - Resource ID Resolution
// ===========================================

var storageAccountResourceId = deployToggles.storage ? storageAccount!.outputs.resourceId : ''
var storageAccountNameValue = deployToggles.storage ? storageAccount!.outputs.name : ''
var keyVaultResourceId = deployToggles.keyVault ? keyVault!.outputs.resourceId : ''
var keyVaultNameValue = deployToggles.keyVault ? keyVault!.outputs.name : ''

// ===========================================
// OUTPUTS - Clean References
// ===========================================

output storageAccountId string = storageAccountResourceId
output storageAccountName string = storageAccountNameValue
output keyVaultId string = keyVaultResourceId
output keyVaultName string = keyVaultNameValue
```

## Multiple Conditions

For resources with multiple conditions, combine them in the variable:

```bicep
module buildVm './vm.bicep' = if (deployToggles.buildVm && !empty(adminPassword) && !empty(subnetId)) {
  name: 'build-vm'
  params: {
    adminPassword: adminPassword
    subnetId: subnetId
  }
}

// Variable combines all conditions
var buildVmResourceId = (deployToggles.buildVm && !empty(adminPassword) && !empty(subnetId)) ? buildVm!.outputs.resourceId : ''

// Output is clean
output buildVmId string = buildVmResourceId
```

## Pattern Structure

```bicep
// 1. MODULE - Define with conditional deployment
module <name> '<path>' = if (<condition>) {
  // module definition
}

// 2. VARIABLE - Resolve output with same condition + ! operator
var <name>ResourceId = <condition> ? <moduleName>!.outputs.resourceId : ''

// 3. OUTPUT - Reference variable
output <name>Id string = <name>ResourceId
```

## Benefits

1. **No Compilation Errors**: Variables properly handle conditional module references
2. **Type Safety**: Variables resolve types before outputs consume them
3. **Readability**: Clear separation between conditional logic (variables) and output declarations
4. **Maintainability**: Easy to add new outputs by following the same pattern
5. **Microsoft Pattern**: This is the official pattern used in AI Landing Zone

## Common Mistakes

### ❌ Direct Conditional in Output
```bicep
output id string = condition ? module!.outputs.resourceId : ''
// Error: Cannot use conditional operator in output
```

### ❌ Missing Non-Null Assertion
```bicep
var id = condition ? module.outputs.resourceId : ''
// Error: module may be null
```

### ❌ Inconsistent Conditions
```bicep
module myModule './module.bicep' = if (deployToggles.toggle1) { }
var id = deployToggles.toggle2 ? myModule!.outputs.resourceId : ''
// Logic error: conditions don't match
```

## Real-World Application

This pattern is used throughout this repository in all 5 deployment stages:
- `infra/orchestrators/stage1-networking.bicep` - 17 variables for network resources
- `infra/orchestrators/stage2-monitoring.bicep` - 3 variables for monitoring
- `infra/orchestrators/stage3-security.bicep` - 3 variables for security
- `infra/orchestrators/stage4-data.bicep` - 5 variables for data services
- `infra/orchestrators/stage5-compute-ai.bicep` - 9 variables for compute/AI

## References

- [Azure AI Landing Zone](https://github.com/Azure/ai-landing-zone)
- [Bicep Conditional Deployment](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/conditional-resource-deployment)
- [Bicep Outputs](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/outputs)

---

**Key Takeaway**: Always use intermediate variables to resolve conditional module outputs before referencing them in output declarations. This is the recommended Bicep pattern for modular deployments.
