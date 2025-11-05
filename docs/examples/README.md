# Fabric Networking Automation Examples

This folder collects sample configuration files that demonstrate how to compose the existing automation scripts in different ways. Use these as starting points when you need to tailor the deployment experience for specific developers or environments.

## Contents

- `azure.yaml.private-networking.sample`: Example `azure.yaml` post-provision hook sequence that only enables Fabric private networking for an existing workspace.
- `fabric-networking.parameters.sample.json`: Minimal parameter file showing the subset of Bicep parameters typically needed when you are layering private networking on top of an existing AI Landing Zone deployment.

## Usage Notes

1. Copy the sample file that matches your scenario into your project (for example, `cp docs/examples/azure.yaml.private-networking.sample azure.yaml`).
2. Adjust the hook list to match the scripts you want to run. All scripts already load `azd env` values, so no manual environment management is required.
3. Update the parameter sample with the values that make sense for your environment (subscription, Purview settings, workspace name, etc.).

Because the automation scripts are intentionally small and idempotent, you can:

- Keep the full pipeline (domain creation, workspace creation, private link, Purview, etc.).
- Run only the networking steps against an existing workspace.
- Execute the cleanup script when you need to remove protected workspaces created during testing.

Refer to the comments inside each sample for more guidance.
