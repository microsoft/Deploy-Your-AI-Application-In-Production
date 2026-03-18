# PostgreSQL Mirroring to Fabric

This guide explains how to complete PostgreSQL mirroring in Microsoft Fabric after deployment.

## Automation status

What is automated today:

- PostgreSQL server prep (roles, grants, seed table, parameters).
- Fabric connection creation or reuse for PostgreSQL mirroring.
- Mirror creation after the Fabric connection is resolved.

## Why a Fabric Connection Is Required

The Fabric mirroring API requires a Fabric "connection" object that stores the PostgreSQL endpoint and credentials. The mirror call only accepts a `connectionId` and database name, so a valid Fabric connection must exist before mirroring can be created.

## Prerequisites

- Deployment finished, and PostgreSQL Flexible Server exists.
- You can sign in to Fabric (app.fabric.microsoft.com) with access to the workspace.
- PostgreSQL authentication mode is **PostgreSQL and Microsoft Entra authentication** (password auth enabled).
- You have access to the Key Vault that stores the PostgreSQL secrets.
- Decide which connection mode you are using: `fabricUser` (default) or `admin` via `postgreSqlMirrorConnectionMode`.

## Step 1: Confirm PostgreSQL Details

Get the PostgreSQL server FQDN and database name:

- FQDN: from `azd env get-value postgreSqlServerFqdn`
- Database name: `postgres` (default) or your custom DB
- Connection mode: from `azd env get-value postgreSqlMirrorConnectionModeOut`
- Fabric login: from `azd env get-value postgreSqlMirrorConnectionUserNameOut`
- Fabric password secret name: from `azd env get-value postgreSqlMirrorConnectionSecretNameOut`

## Step 2: Prepare the Database (Automated by Default)

The mirroring prep script configures the server and creates a seed table so Fabric always finds at least one table to replicate.

### Automated (recommended)

Run:

```powershell
pwsh ./scripts/automationScripts/FabricWorkspace/Mirror/prepare_postgresql_for_mirroring.ps1
```

If you are running from a non-VNet host and the Key Vault blocks public access, set:

```powershell
$env:POSTGRES_TEMP_ENABLE_KV_PUBLIC_ACCESS = 'true'
```

What it does now:

- Creates or validates the `fabric_user` role when mode is `fabricUser`.
- Ensures PostgreSQL auth modes are enabled (password + Entra).
- Grants `azure_cdc_admin` and database permissions.
- Creates a seed table: `public.fabric_mirror_seed` (owned by the mirroring identity, either `fabric_user` or `pgadmin`).
- Uses `psql` fallback when `rdbms-connect` cannot install.

### Manual (only if automation fails)

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
pwsh ./scripts/automationScripts/FabricWorkspace/Mirror/create_postgresql_mirror.ps1
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
./scripts/automationScripts/FabricWorkspace/Mirror/create_postgresql_mirror.ps1
```

## Verify

- In Fabric, a mirrored database named `pg-mirror-<env>` should appear.
- Re-running the script is safe; it will skip if the mirror already exists.

## Notes

- The deployment now attempts to create or reuse the Fabric PostgreSQL connection automatically before creating the mirror.
- If automatic connection creation cannot reach Key Vault or the source database, the script exits without failing the entire deployment and leaves a manual fallback path.
- If you rotate passwords, update the Fabric connection in the workspace.

## Troubleshooting

### Invalid credentials

- Ensure PostgreSQL auth is **PostgreSQL and Microsoft Entra authentication** (password auth enabled).
- Use the login from `postgreSqlMirrorConnectionUserNameOut` in the Fabric connection.
- Verify the Key Vault secret named by `postgreSqlMirrorConnectionSecretNameOut` matches the chosen connection credential.

### Private networking or gateway-required sources

- If the PostgreSQL server is private-only, set `fabricPostgresGatewayId` in `azd` before rerunning the script so the connection is created under the Fabric VNet gateway.
- If the gateway ID is not set, the automation uses a shareable cloud connection.

### Must be owner of table

If Fabric reports `must be owner of table <table>`:

```sql
ALTER TABLE public.fabric_mirror_seed OWNER TO "fabric_user";
```
