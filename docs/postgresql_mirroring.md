# PostgreSQL Mirroring to Fabric

This guide explains how to complete PostgreSQL mirroring in Microsoft Fabric after deployment.

## Automation status

What is automated today:

- PostgreSQL server prep (roles, grants, seed table, parameters).
- Mirror creation **after** a Fabric connection exists (scripted).

What is still manual and why:

- Fabric connection creation is **portal-only** today. The public Fabric API does not currently expose a supported endpoint to create PostgreSQL connections, so the connection must be created in the UI to obtain a `connectionId`.

Once Fabric exposes a supported API for connection creation, this step can be fully automated.

## Why a Fabric Connection Is Required

The Fabric mirroring API requires a Fabric "connection" object that stores the PostgreSQL endpoint and credentials. The mirror call only accepts a `connectionId` and database name, so a valid Fabric connection must exist before mirroring can be created.

## Prerequisites

- Deployment finished, and PostgreSQL Flexible Server exists.
- You can sign in to Fabric (app.fabric.microsoft.com) with access to the workspace.
- PostgreSQL authentication mode is **PostgreSQL and Microsoft Entra authentication** (password auth enabled).
- You have access to the Key Vault that stores the PostgreSQL secrets.

## Step 1: Confirm PostgreSQL Details

Get the PostgreSQL server FQDN and database name:

- FQDN: from `azd env get-value postgreSqlServerFqdn`
- Database name: `postgres` (default) or your custom DB
- Admin login: `pgadmin`
- Fabric login: `fabric_user` (used by Fabric)
- Fabric password: Key Vault secret `postgres-fabric-user-password`

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

- Creates or validates the `fabric_user` role.
- Ensures PostgreSQL auth modes are enabled (password + Entra).
- Grants `azure_cdc_admin` and database permissions.
- Creates a seed table: `public.fabric_mirror_seed` (owned by the mirroring user when created as `fabric_user`).
- Uses `psql` fallback when `rdbms-connect` cannot install.

### Manual (only if automation fails)

Connect as `pgadmin@<server-name>` in the `postgres` database and run:

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

## Step 3: Create the Fabric Connection (UI)

1. Open the Fabric workspace.
2. Go to **Settings** -> **Manage connections and gateways**.
3. Select **New connection** -> **PostgreSQL**.
4. Enter:
   - Server: PostgreSQL FQDN (example: `pg-<env>.postgres.database.azure.com`)
   - Database: `postgres` (or your custom DB)
   - User: `fabric_user@<server-name>` (example: `fabric_user@pg-dev031126a`)
   - Password: value from Key Vault secret `postgres-fabric-user-password`
5. Save and copy the **Connection ID**.

## Step 4: Set the Connection ID in azd

```powershell
azd env set-value fabricPostgresConnectionId "<connection-id>"
azd env set-value POSTGRES_DATABASE_NAME "postgres"
```

## Step 5: Create the Mirror

Run the mirror script (this is the automation step after the connection exists):

```powershell
./scripts/automationScripts/FabricWorkspace/Mirror/create_postgresql_mirror.ps1
```

## Verify

- In Fabric, a mirrored database named `pg-mirror-<env>` should appear.
- Re-running the script is safe; it will skip if the mirror already exists.

## Notes

- The deployment now skips the mirror step until a valid Fabric connection exists, so `azd up` will no longer fail on this step.
- If you rotate passwords, update the Fabric connection in the workspace.

## Troubleshooting

### Invalid credentials

- Ensure PostgreSQL auth is **PostgreSQL and Microsoft Entra authentication** (password auth enabled).
- Use `fabric_user@<server-name>` in the Fabric connection.
- Verify the Key Vault secret matches the role password. Automation sets it unless it failed.

### Must be owner of table

If Fabric reports `must be owner of table <table>`:

```sql
ALTER TABLE public.fabric_mirror_seed OWNER TO "fabric_user";
```
