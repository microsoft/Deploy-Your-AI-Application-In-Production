// ================================================
// Minimal Main Orchestrator
// ================================================
// This is a minimal orchestrator that only deploys Stage 1 (networking)
// All other stages are deployed via azd hooks to avoid 4MB ARM template limit
// ================================================

targetScope = 'subscription'

metadata name = 'Minimal Main Orchestrator - Stage 1 Only'
metadata description = 'Deploys only networking infrastructure. Other stages deployed via hooks.'

// Import main parameters
using './main-orchestrator.bicep'

