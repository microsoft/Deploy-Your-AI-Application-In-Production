# PostgreSQL Mirroring to Fabric

This guide explains how to complete PostgreSQL mirroring in Microsoft Fabric after deployment.

## Why a Fabric Connection Is Required

The Fabric mirroring API requires a Fabric "connection" object that stores the PostgreSQL endpoint and credentials. The mirror call only accepts a `connectionId` and database name, so a valid Fabric connection must exist before mirroring can be created.

## Prerequisites

- Deployment finished, and PostgreSQL Flexible Server exists.
- Post-provision prep ran (it creates the `fabric_user` role and sets required PostgreSQL flags).
- You can sign in to Fabric (app.fabric.microsoft.com) with access to the workspace.

## Step 1: Confirm PostgreSQL Details

Get the PostgreSQL server FQDN and database name:

- FQDN: from `azd env get-value postgreSqlServerFqdn`
- Database name: `postgres` (default) or your custom DB

## Step 2: Create the Fabric Connection (UI)

1. Open the Fabric workspace.
2. Go to **Settings** -> **Manage connections and gateways**.
3. Select **New connection** -> **PostgreSQL**.
4. Enter:
   - Server: PostgreSQL FQDN
   - Database: your database name
   - User: `fabric_user`
   - Password: value from Key Vault secret `postgres-fabric-user-password`
5. Save and copy the **Connection ID**.

## Step 3: Set the Connection ID in azd

```powershell
azd env set-value fabricPostgresConnectionId "<connection-id>"
azd env set-value POSTGRES_DATABASE_NAME "postgres"
```

## Step 4: Create the Mirror

Run the mirror script:

```powershell
./scripts/automationScripts/FabricWorkspace/Mirror/create_postgresql_mirror.ps1
```

## Verify

- In Fabric, a mirrored database named `pg-mirror-<env>` should appear.
- Re-running the script is safe; it will skip if the mirror already exists.

## Notes

- The deployment now skips the mirror step until a valid Fabric connection exists, so `azd up` will no longer fail on this step.
- If you rotate passwords, update the Fabric connection in the workspace.
