# OneLake Index Setup Summary
# Complete automation for indexing OneLake documents in Azure AI Search

Write-Host "=================================================================="
Write-Host "OneLake Index Setup - Complete Automation"
Write-Host "=================================================================="
Write-Host ""
Write-Host "This folder contains the complete OneLake indexing automation:"
Write-Host ""
Write-Host "📋 Setup Scripts (run in order):"
Write-Host "  0. 00_setup_rbac.ps1                - Sets up RBAC permissions for AI Search"
Write-Host "  1. 01_create_onelake_skillsets.ps1  - Creates AI skillsets for document processing"
Write-Host "  2. 02_create_onelake_datasource.ps1 - Creates OneLake data source connection" 
Write-Host "  3. 03_create_onelake_indexer.ps1    - Creates and runs the OneLake indexer"
Write-Host "  4. 04_debug_onelake_indexer.ps1     - Debugging and status checking"