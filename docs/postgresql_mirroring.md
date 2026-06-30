# PostgreSQL Mirroring to Fabric

This guide explains how to complete PostgreSQL mirroring in Microsoft Fabric after deployment.

> **Security-critical note:** The mirroring prep script must run from a VNet-connected host when Key Vault and PostgreSQL are private. If you want to demo the full end-to-end mirroring flow from a non-VNet machine, you must temporarily open access to both Key Vault and PostgreSQL before running the script, then re-lock them afterward. Treat this as a deliberate security step, not a default configuration.

> **Resource naming note:** The AI Landing Zone submodule deploys Foundry and agent resources with an `ai-` prefix, including a separate Key Vault, Storage Account, and Cosmos DB. PostgreSQL mirroring uses the main deployment Key Vault from `keyVaultResourceId` (this is where the `postgreSql*` secrets live), not the `ai-` prefixed Key Vault. When a step says "Key Vault" in this doc, use the Key Vault from `keyVaultResourceId`.
>
> **How to find `keyVaultResourceId`:**
> - Run `azd env get-value keyVaultResourceId` from the repo root.
> - Or run `azd env get-values` and look for `keyVaultResourceId`.
> - Or in Azure Portal, open the Key Vault used for deployment and copy its **Resource ID** from the **Overview** blade.

Mirroring automation in the current branch is set for PostgreSQL deployments where `postgreSqlNetworkIsolation = false`.

For the public/manual path, this repo now supports a declarative firewall toggle through `postgreSqlAllowAzureServices`.

- `postgreSqlNetworkIsolation = false` makes PostgreSQL publicly reachable.
- `postgreSqlAllowAzureServices = true` creates the PostgreSQL `AllowAzureServices` firewall rule (`0.0.0.0` to `0.0.0.0`), which is the deployment equivalent of the Azure portal **Allow public access from any Azure service within Azure to this server** setting.
- That combination is the recommended configuration when you want `azd up` to leave PostgreSQL ready for a manual Fabric connection without using a VNet gateway.

If you want full PostgreSQL isolation, the database deployment can still succeed, but end-to-end Fabric mirroring moves to the Fabric VNet gateway path.

If you are not changing the network approach right now, there are only two valid post-deployment outcomes:

1. Use a public-network path that lets Fabric reach PostgreSQL, then complete the mirror.
2. Keep PostgreSQL private and treat mirroring as deferred.

Do not expect a private-endpoint PostgreSQL deployment to produce a working Fabric mirror during the main deployment workflow alone.

## Common Manual Flow (Non-VM Runner)

This is the most common flow when you run `azd up` from a non-VNet machine. The postprovision mirroring prep often fails because Key Vault and PostgreSQL are private, so you finish the mirror manually.

### Public Access Enabled

Follow this path when the PostgreSQL server has `publicNetworkAccess=Enabled`. In this repo, that corresponds to `postgreSqlNetworkIsolation = false`.

Recommended deployment settings for this path:

```bicep-params
param postgreSqlNetworkIsolation = false
param postgreSqlAllowAzureServices = true
```

1. Run `azd up` and let postprovision finish (mirroring prep may warn on a non-VNet host).
2. In Azure Portal, open the Key Vault from `keyVaultResourceId` and temporarily enable public networking so you can copy the password:
   - Azure Portal -> search for **Key Vaults** -> select the Key Vault that matches the name in the resource ID
   - Go to **Networking** -> set **Public network access** to **Enabled**
   - Select **Apply** to save
3. Copy the `fabric_user` password from that Key Vault (you will paste it into the Fabric connection wizard):

```powershell
azd env get-value postgreSqlMirrorConnectionSecretNameOut
az keyvault secret show --vault-name <keyvault-name> --name <secret-name> --query value -o tsv
```

4. In Fabric, create a new **Mirrored Azure Database for PostgreSQL** item:
    - Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com) and open your workspace (for example, `workspace-<envname>`)
    - Select **New item** -> **Mirror data** -> **Azure Database for PostgreSQL**
    - Enter:
       - Server: PostgreSQL FQDN from `azd env get-value postgreSqlServerFqdn`
       - Database: `postgres` (or your custom DB)
       - Username: `fabric_user`
       - Password: the Key Vault secret value
   - For full portal screenshots and walkthrough, see [Tutorial: Configure Microsoft Fabric mirrored databases from Azure Database for PostgreSQL](https://learn.microsoft.com/fabric/mirroring/azure-database-postgresql-tutorial).

5. Choose **Select data**, pick the `public.fabric_mirror_seed` table, preview the row, then select **Connect**.
6. On the next screen, name the mirror (or accept the default) and select **Create mirrored database**.
7. Verify the mirrored database appears.
8. Re-lock the Key Vault by disabling public networking after the connection succeeds.

If the database or login fails, confirm `postgreSqlAllowAzureServices = true` (or add the `0.0.0.0` firewall rule).

### Private Network or Private Endpoint

Follow this path when the PostgreSQL server is private-only or Fabric cannot reach it over public networking.

You must supply a Fabric VNet gateway ID for the connection flow in this mode. The repo may add a gateway option in a future update, but today you need to bring your own gateway and set `fabricPostgresGatewayId` before creating the connection.

1. Treat mirroring as deferred for this provisioning cycle.
2. Use the PostgreSQL server's **Fabric Mirroring** page in Azure Portal only if you want to confirm the source-server prerequisite experience.
3. Continue validating the rest of the deployment: Fabric workspace, lakehouses, PostgreSQL server, AI Search, and Purview.
4. For end-to-end mirroring with PostgreSQL kept private, use the Fabric VNet gateway route.

### What to Do First

If you want the shortest path to a working mirror, follow the **Public Access Enabled** flow above.

If you are intentionally staying private for now, skip mirror creation for this provisioning test and continue validating the rest of the deployment.

## Recommended Repo Flow

In this repo, mirroring is prepared during postprovision and only needs a short manual follow-up after the main deployment completes.

That means:

1. `azd up` deploys the infrastructure and runs the mirroring prep automation.
2. PostgreSQL mirroring is not a required same-run success criterion.
3. The only required follow-up is a short manual Fabric registration step (see below).

The cleanest sequence is:

1. Run `azd up`.
2. Validate the deployment with [post_deployment_steps.md](./post_deployment_steps.md).
3. Temporarily enable Key Vault public access (if needed) to retrieve the Fabric user secret.
4. Register the PostgreSQL connection in Fabric and create the mirror.
5. Verify the Fabric connection and mirrored database.

Running from the deployed VM is usually the least fragile option because it avoids local DNS, firewall, VPN, and endpoint-security issues.

### Manual Follow-Up (Required)

After `azd up`, no additional scripts are required. Complete these manual steps:

1. Temporarily enable Key Vault public access (if it is private).
2. Retrieve the Fabric user secret from Key Vault.
3. Register the PostgreSQL connection in Fabric.
4. Create the mirror in Fabric and validate sync.

If you need to troubleshoot connectivity from a runner, use the preflight script as a diagnostic, but it is no longer required for the normal flow.

## Automation status

What is automated today:

- PostgreSQL server deployment during `azd up`.
- Optional PostgreSQL Azure-services firewall rule creation during `azd up` when `postgreSqlAllowAzureServices = true` and PostgreSQL public access is enabled.
- PostgreSQL mirroring prep during `azd up` postprovision (server parameters, auth mode, mirroring role/grants, and seed table).
- Manual or follow-up Fabric connection creation for PostgreSQL mirroring.
- Manual or follow-up mirror creation after the Fabric connection is resolved.

## Why a Fabric Connection Is Required

The Fabric mirroring API requires a Fabric "connection" object that stores the PostgreSQL endpoint and credentials. The mirror call only accepts a `connectionId` and database name, so a valid Fabric connection must exist before mirroring can be created.

## Prerequisites

- Deployment finished, and PostgreSQL Flexible Server exists.
- You can sign in to Fabric (app.fabric.microsoft.com) with access to the workspace.
- PostgreSQL authentication mode is **PostgreSQL and Microsoft Entra authentication** (password auth enabled).
- You have access to the Key Vault that stores the PostgreSQL secrets. (will require either connection via jumpbox vm, or temporarily enabling public access to keyvault to get the fabricUser secret)
- Decide which connection mode you are using: `fabricUser` (default) or `admin` via `postgreSqlMirrorConnectionMode`.
- If you are using the public/manual path, prefer `postgreSqlAllowAzureServices = true` so Fabric can reach PostgreSQL without a VNet gateway.

## Step 1: Confirm PostgreSQL Details

Get the PostgreSQL server FQDN and database name:

- FQDN: from `azd env get-value postgreSqlServerFqdn`
- Database name: `postgres` (default) or your custom DB
- Connection mode: from `azd env get-value postgreSqlMirrorConnectionModeOut`
- Fabric login: from `azd env get-value postgreSqlMirrorConnectionUserNameOut`
- Fabric password secret name: from `azd env get-value postgreSqlMirrorConnectionSecretNameOut`

## Step 2: Prepare the Database (Run Automatically During Postprovision)

The mirroring prep script configures the server and creates a seed table so Fabric always finds at least one table to replicate. It runs during `azd up` postprovision.

What it does:

- Invokes Azure-side Fabric mirroring enablement for the selected database when available.
- Creates or validates the `fabric_user` role when mode is `fabricUser`.
- Ensures PostgreSQL auth modes are enabled (password + Entra).
- Grants `azure_cdc_admin` and database permissions.
- Creates a seed table: `public.fabric_mirror_seed` (owned by the mirroring identity, either `fabric_user` or `pgadmin`).
- Uses `psql` fallback when `rdbms-connect` cannot install.

### Manual (only if automation fails)

If your deployment allows public access, the shortest supported fallback is usually the server's **Fabric Mirroring** page in Azure Portal instead of running these SQL statements manually.

Use that portal page only for the server-side prerequisite work. You still need either the automation or a manual Fabric connection and mirrored database creation step afterward.

Connect as `pgadmin` in the `postgres` database and run:

```sql
CREATE ROLE "fabric_user" CREATEDB CREATEROLE LOGIN REPLICATION PASSWORD '<fabric_user_password>';
GRANT azure_cdc_admin TO "fabric_user";
GRANT CREATE ON DATABASE "postgres" TO "fabric_user";
GRANT USAGE ON SCHEMA public TO "fabric_user";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "fabric_user";

CREATE TABLE IF NOT EXISTS public.fabric_mirror_seed (
   id bigserial PRIMARY KEY,
   created_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.fabric_mirror_seed (created_at)
SELECT now()
WHERE NOT EXISTS (SELECT 1 FROM public.fabric_mirror_seed);

ALTER TABLE public.fabric_mirror_seed OWNER TO "fabric_user";
```

Update the Key Vault secret after you set the password (automation already does this unless it failed):

```powershell
az keyvault secret set --vault-name <keyvault-name> --name postgres-fabric-user-password --value "<fabric_user_password>"
```

> Ownership note: Fabric requires the mirror user to own tables. If you create tables as `pgadmin`, change ownership to `fabric_user`.

## Step 3: Create or Reuse the Fabric Connection (Automated by Default)

Run:

```powershell
pwsh ./scripts/automationScripts/FabricWorkspace/mirror/create_postgresql_mirror.ps1
```

What the script does now:

- Reuses `fabricPostgresConnectionId` when it is already stored in `azd`.
- Otherwise resolves the connection login from `postgreSqlMirrorConnectionUserNameOut`.
- Resolves the connection password secret name from `postgreSqlMirrorConnectionSecretNameOut`.
- Reads the chosen secret from Key Vault, creates or reuses the Fabric PostgreSQL connection, and stores the resulting `fabricPostgresConnectionId` back into `azd`.
- Creates the mirrored database after the connection is available.

If your PostgreSQL server is reachable only through a Fabric VNet data gateway, set the gateway ID before rerunning the script:

```powershell
azd env set-value fabricPostgresGatewayId "<fabric-vnet-gateway-id>"
```

Without `fabricPostgresGatewayId`, the script creates a standard cloud connection.

### Manual fallback

If your deployment has public access enabled, try the **Minimal Manual Fallback** section first. It is shorter than manually creating the Fabric connection from scratch.

If you need to create the Fabric connection manually, do not hardcode `fabric_user`, `pgadmin`, or the secret name. Read the values from the deployment outputs first:

```powershell
azd env get-value postgreSqlMirrorConnectionModeOut
azd env get-value postgreSqlMirrorConnectionUserNameOut
azd env get-value postgreSqlMirrorConnectionSecretNameOut
```

Then in Fabric:

1. Open the Fabric workspace.
2. Go to **Settings** -> **Manage connections and gateways**.
3. Select **New connection** -> **PostgreSQL**.
4. Enter:
   - Server: PostgreSQL FQDN (example: `pg-<env>.postgres.database.azure.com`)
   - Database: `postgres` (or your custom DB)
   - User: the value from `postgreSqlMirrorConnectionUserNameOut`
   - Password: the Key Vault secret value stored under `postgreSqlMirrorConnectionSecretNameOut`
5. Save and copy the **Connection ID**.

## Step 4: Persist the Connection ID in azd (only if you created it manually)

```powershell
azd env set-value fabricPostgresConnectionId "<connection-id>"
azd env set-value POSTGRES_DATABASE_NAME "postgres"
```

## Step 5: Create the Mirror

If the previous script already created the connection automatically, re-running it is safe and idempotent. If you created the connection manually, run it once now:

```powershell
./scripts/automationScripts/FabricWorkspace/mirror/create_postgresql_mirror.ps1
```

## Verify

- In Fabric, a mirrored database named `pg-mirror-<env>` should appear.
- Re-running the script is safe; it will skip if the mirror already exists.

## Notes

- The deployment now attempts to create or reuse the Fabric PostgreSQL connection automatically before creating the mirror.
- If automatic connection creation cannot reach Key Vault or the source database, the script leaves a manual fallback path.
- Without public reachability or `fabricPostgresGatewayId`, a private PostgreSQL server is not expected to mirror successfully.
- If you rotate passwords, update the Fabric connection in the workspace.

## Troubleshooting

### Invalid credentials

- Ensure PostgreSQL auth is **PostgreSQL and Microsoft Entra authentication** (password auth enabled).
- Use the login from `postgreSqlMirrorConnectionUserNameOut` in the Fabric connection.
- Verify the Key Vault secret named by `postgreSqlMirrorConnectionSecretNameOut` matches the chosen connection credential.

### Private networking or gateway-required sources

- If the PostgreSQL server is private-only, set `fabricPostgresGatewayId` in `azd` before rerunning the script so the connection is created under the Fabric VNet gateway.
- If the gateway ID is not set, the automation uses a shareable cloud connection.
- If automation still cannot complete SQL prep from your machine, use the PostgreSQL server's **Fabric Mirroring** page first, then fall back to a Bastion or other VNet-connected host only if needed.

### Must be owner of table

If Fabric reports `must be owner of table <table>`:

```sql
ALTER TABLE public.fabric_mirror_seed OWNER TO "fabric_user";
```
