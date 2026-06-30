# Fabric Workspace Cleanup Script

This folder contains a utility for cleaning up Microsoft Fabric workspaces that are not connected to any capacity and cannot be deleted through the UI.

## Script

### `cleanup_orphaned_fabric_workspaces.ps1`

**Purpose**: Identifies and deletes Fabric workspaces that are not connected to any active capacity.

**Key Features**:
- **Preserves** workspaces assigned to inactive capacities (you're still working on them)
- **Deletes** only workspaces with no capacity assignment at all
- **Safety features**: Preview mode, confirmation prompts, exclusion lists
- **Uses Power BI API**: Proven to work when Fabric API fails
- **Security focused**: Tokens are handled securely and cleared from memory

**Usage**:
```powershell
# Preview mode - see what would be deleted without making changes
./cleanup_orphaned_fabric_workspaces.ps1 -WhatIf

# Delete orphaned workspaces (with confirmation prompt)
./cleanup_orphaned_fabric_workspaces.ps1

# Delete without confirmation prompt
./cleanup_orphaned_fabric_workspaces.ps1 -Force

# Exclude specific workspaces from deletion
./cleanup_orphaned_fabric_workspaces.ps1 -ExcludeWorkspaces @('My workspace', 'Important Workspace')

# Only delete workspaces older than 14 days
./cleanup_orphaned_fabric_workspaces.ps1 -MaxAge 14
```

**Parameters**:
- `-WhatIf`: Preview mode - shows what would be deleted without making changes
- `-Force`: Skip confirmation prompt
- `-ExcludeWorkspaces`: Array of workspace names to exclude from deletion
- `-MaxAge`: Only consider workspaces older than this many days (default: 7)

## Prerequisites

1. **Azure CLI**: Must be installed and authenticated
   ```bash
   az login
   ```

2. **PowerShell**: Script requires PowerShell 5.1 or PowerShell Core 6+

3. **Fabric Permissions**: Your account must have appropriate permissions to:
   - List Fabric workspaces
   - Delete workspaces

## How It Works

The script:
1. **Uses Fabric API** to list workspaces and check capacity assignments
2. **Uses Power BI API** to delete workspaces (more reliable than Fabric API)
3. **Identifies orphaned workspaces** as those with NO capacity assignment
4. **Preserves workspaces** that are assigned to inactive capacities
5. **Applies safety filters** like age limits and exclusion lists

## Example Output

```
[cleanup] Found orphaned workspace: test-ws1 (Capacity: None)
[cleanup] Found orphaned workspace: old-sandbox (Capacity: None)
[cleanup] Keeping workspace with inactive capacity: dev-workspace → devcapacity (Inactive)

[cleanup] ✅ Deleted: test-ws1
[cleanup] ✅ Deleted: old-sandbox
[cleanup] ✅ Cleanup completed! Removed 2 orphaned workspaces
```

## Security Features

The script implements several security best practices:

1. **Secure Token Handling**: API tokens are never logged or displayed in plain text
2. **Memory Cleanup**: Sensitive variables are securely cleared from memory after use
3. **Error Sanitization**: Error messages are sanitized to prevent token exposure
4. **Minimal Token Exposure**: Tokens are only used within secure header functions

**Important**: Ensure you run this script in a secure environment and that your Azure CLI session is properly authenticated.

## Troubleshooting

### Authentication Issues
```
Error: Failed to obtain API token
```
**Solution**: Run `az login` to authenticate with Azure CLI

### No Workspaces Found
If the script reports no orphaned workspaces, this means:
- All workspaces are properly assigned to active capacities, OR
- All unassigned workspaces are in the exclusion list, OR  
- All unassigned workspaces are newer than the age filter

Use `-WhatIf` mode to see the analysis without making changes.

### Permission Issues
Ensure your account has the necessary Fabric workspace permissions. The script requires the same permissions you would need to delete workspaces manually through the portal.

## Success Story

This script successfully solved the problem where orphaned Fabric workspaces couldn't be deleted through the UI due to missing capacity assignments. The combination of Fabric API for workspace analysis and Power BI API for deletion provides a reliable automated solution.