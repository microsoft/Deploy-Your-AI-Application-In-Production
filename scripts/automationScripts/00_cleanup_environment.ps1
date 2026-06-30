# Clean up any stale environment files from previous deployments
# This ensures each deployment starts with a clean state

Write-Host "Cleaning up stale environment files..."

# Remove any existing fabric environment files from /tmp
$filesToRemove = @(
    (Join-Path ([IO.Path]::GetTempPath()) "fabric_workspace.env"),
    (Join-Path ([IO.Path]::GetTempPath()) "fabric_datasource.env"), 
    (Join-Path ([IO.Path]::GetTempPath()) "fabric_lakehouses.env")
)

foreach ($file in $filesToRemove) {
    if (Test-Path $file) {
        Remove-Item $file -Force
        Write-Host "Removed: $file"
    }
}

Write-Host "Environment cleanup completed."
