# Terraform blueprint for the student-friendly Azure stack

This repository contains modular Terraform that stands up a small Azure footprint tailored for Azure for Students subscriptions: one Linux VM that runs your containerized workload and a managed PostgreSQL Flexible Server, with an Azure Key Vault for application secrets and automation to keep costs predictable. The accompanying GitHub Actions pipeline deploys it **secretlessly** (Azure login via OpenID Connect, no long-lived credentials) and the VM reads its runtime configuration from Key Vault using its own managed identity.

## Architecture overview

Everything lives in a single resource group whose name is derived from `environment_name` (normalized and truncated to 45 characters). The Terraform is split into reusable modules under [`modules/`](modules/):

| Module | Resources |
| --- | --- |
| **network** | /16 virtual network with one VM subnet, NSG (HTTP/HTTPS open, SSH limited to `allowed_admin_cidrs`), public IP (dynamic by default, switchable to static), NIC. |
| **compute** | Ubuntu 22.04 LTS VM with a 64 GB Premium SSD OS disk, SSH-key auth only, and a **system-assigned managed identity**. |
| **database** | PostgreSQL Flexible Server (Basic B1ms, 32 GB, auto-grow off by default to stay in the free tier), the default `postgres` database, and firewall rules for Azure services and (optionally) the VM public IP. |
| **storage** | Optional Azure Storage Account for blobs (`blob_storage_enabled`), Standard LRS, TLS 1.2 only, public access disabled, with **blob versioning and 7-day soft delete** for recoverability. |
| **automation** | Azure Automation account + runbooks, created only when at least one automation feature is enabled (VM start/stop schedules, ad-hoc snapshots, snapshot cleanup, on-demand PostgreSQL backups). |
| **keyvault** | Azure Key Vault holding the application secrets (see *Secret management* below), with access policies for the pipeline (read/write) and the VM identity (read). |

The root module wires the modules together, owns the resource group, and exposes connection details (SSH command, VM IP, database FQDN/connection string, storage account name) as outputs.

## Authentication (secretless / OIDC)

The pipeline authenticates to Azure through **workload identity federation (OpenID Connect)** — there is no Service Principal secret stored anywhere:

- `azure/login` exchanges a short-lived GitHub OIDC token for an Azure access token, using the `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` **repository variables** (these are identifiers, not secrets).
- The deployment job runs in the `production` GitHub environment, so the OIDC token's subject matches a **federated credential** registered on the Azure app registration.

## Secret management (Key Vault)

Application secrets live in Azure Key Vault rather than in the application repository:

- The pipeline assembles the full application environment (static base + the live database connection and, when enabled, the storage account credentials) and publishes it to Key Vault as the `app-env` secret. The static base is seeded once from `APP_ENV_VARS_B64` and thereafter stored as `app-env-base`.
- The database connection string and the storage account name/key are also stored as individual Key Vault secrets.
- At deploy time the **VM fetches `app-env` from Key Vault using its managed identity** (via the instance metadata service) and writes `app.env`; the container then starts with `--env-file`. No application secret is copied over SSH.

## Remote state

Terraform state is stored remotely in Azure Storage so that it survives ephemeral CI runners, is shared across machines, and is protected against concurrent writes (the `azurerm` backend takes a blob lease, which stops two `terraform apply` runs from corrupting the state at the same time).

The backend is **bootstrapped automatically by the pipeline** — no manual setup, no extra file or secret:

- `versions.tf` declares an empty `backend "azurerm" {}`; the concrete settings are injected at `init` time via `-backend-config`.
- On every run the workflow ensures the backing resources exist (create-if-missing, idempotent):
  - **Resource group** `tfstate-rg`
  - **Storage account** named `<environment_name><suffix>`, where the suffix is derived deterministically from the subscription ID (globally unique yet stable across runs)
  - **Container** `tfstate`, state stored under the key `docker2azure.tfstate`
- The state storage account has **blob versioning** and **soft delete** (7 days) enabled, so a bad apply can be recovered.

To work against the same remote state locally, initialise with the matching backend settings:

```bash
terraform init \
  -backend-config=resource_group_name=tfstate-rg \
  -backend-config=storage_account_name=<the-account-name> \
  -backend-config=container_name=tfstate \
  -backend-config=key=docker2azure.tfstate
```

## Automation toggles

| Feature | Variables | What it does |
| --- | --- | --- |
| VM daily schedule | `vm_schedule_enabled`, `vm_schedule_start_time`, `vm_schedule_stop_time`, `vm_schedule_timezone` | Automation runbooks + schedules that start/stop the VM daily to save credits. |
| Manual VM snapshot | `vm_snapshot_runbook_enabled` | Deploys the `*-snapshot` runbook for on-demand OS-disk snapshots. |
| Snapshot cleanup | `vm_snapshot_cleanup_enabled`, `vm_snapshot_retention_days`, `vm_snapshot_cleanup_time`, `vm_snapshot_cleanup_timezone` | Scheduled runbook that deletes snapshots older than the retention window. |
| PostgreSQL on-demand backup | `db_backup_enabled`, `db_backup_time`, `db_backup_timezone` | Runbook + schedule that calls the Flexible Server REST API for an extra daily backup. |

Set the boolean flags to `false` when you do not need a capability; Terraform skips the related Automation modules, runbooks, schedules, and job bindings.

## Prerequisites

- Terraform >= 1.5 and the Azure CLI installed locally.
- An Azure subscription. The pipeline uses OIDC federated credentials; for local runs an `az login` session is enough.
- An SSH public key (ed25519 or RSA) that becomes the only authentication method for the VM.
- Optional: Docker and `jq` if you want to reproduce the GitHub Actions workflow locally.

## Configure variables

1. Copy the template and adjust the values:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` and provide:
   - `subscription_id` / `tenant_id` when not relying on the logged-in Azure CLI identity.
   - `environment_name`, `location`, and your SSH public key (`admin_ssh_public_key`).
   - Database credentials (`db_admin_username`, `db_admin_password`).
   - Any CIDR ranges that should reach the VM via SSH/HTTP/HTTPS.

3. When a pipeline needs to read a subset of values, use the helper script:

   ```bash
   python scripts/tfvars_meta.py terraform.tfvars subscription_id environment_name
   ```

   It prints `key=value` pairs and fails if any key is missing, which is handy inside GitHub Actions.

## Deploy the stack

```bash
az login
az account set --subscription <subscription-id>

# Initialise against the shared remote state (see "Remote state" above)
terraform init \
  -backend-config=resource_group_name=tfstate-rg \
  -backend-config=storage_account_name=<the-account-name> \
  -backend-config=container_name=tfstate \
  -backend-config=key=docker2azure.tfstate
terraform plan
terraform apply
```

Use `terraform destroy` when you no longer need the environment (export database data and Key Vault secrets beforehand).

## Outputs and what to do with them

- `resource_group_name` – Scope Azure CLI commands after deployment.
- `vm_public_ip` / `ssh_connection_string` – Connect to the VM.
- `database_fqdn` / `database_connection_string` – Configure your application. The connection string uses TLS (`sslmode=require`).
- `storage_account_name` – Available only when `blob_storage_enabled = true`.
- `key_vault_name` – The Key Vault that holds the application secrets.

## Day-2 operations

- **Snapshots** – Run the `*-snapshot` runbook from the Automation account, providing the resource group and VM name.
- **Cleanup** – When enabled, the `*-snapshot-cleanup` runbook runs daily and deletes snapshots older than `vm_snapshot_retention_days`.
- **Database backups** – Terraform configures platform backups (PITR) via `backup_retention_days`; the optional backup runbook adds an extra manual restore point.
- **Firewall adjustments** – Update `allowed_admin_cidrs` and reapply. Switching to a static public IP also adds the matching database firewall rule.

## GitHub Actions integration

The `sync/...` branches used by deployment automation are temporary delivery branches, not feature branches. Before any important infrastructure change, update the affected README or `.md` files (Terraform variables, deployment flow, required secrets, operational runbooks).

### Pull request validation

Every pull request targeting `main` runs [`.github/workflows/pr-validation.yml`](.github/workflows/pr-validation.yml):

1. `terraform fmt -check` and `terraform validate` always run (no cloud credentials required).
2. When Azure access is configured, it also runs `terraform plan` against the live remote state.
3. The validation output (and the plan, when produced) is published as a build artifact.

### Security scanning

[`.github/workflows/security-scan.yml`](.github/workflows/security-scan.yml) runs Trivy on every push and pull request:

- **IaC misconfiguration scan** of the Terraform (fails the job on `CRITICAL`/`HIGH` findings; an accepted baseline is documented in [`.trivyignore`](.trivyignore)).
- **Secret scan** of the working tree.
- Results are also uploaded as SARIF to the GitHub *Security* tab where Advanced Security is available.

### Continuous deployment

[`.github/workflows/deploy-from-sync.yml`](.github/workflows/deploy-from-sync.yml) runs on a short-lived `sync/...` branch that carries a `sync-bundle/` directory with the application artifacts and Dockerfile. The job:

1. Logs in to Azure via **OIDC** and ensures the remote state backend exists.
2. On a brand-new environment, adopts any pre-existing Azure resources into state; on a populated state this step is skipped.
3. Runs `terraform plan -out=tfplan`, publishes the plan as an artifact, and applies **exactly that plan**.
4. Builds and pushes the container image, publishes the assembled `app-env` to Key Vault, and has the VM load it via its managed identity.
5. Redeploys the container over SSH and always deletes the temporary NSG rule and the `sync/...` branch when it finishes.

Refer to `AUTOMATION.md` for the full automation playbook, including required secrets/variables and how the application and infrastructure repositories coordinate.

## Repository layout

```text
.
├── main.tf                # Root module: resource group + module wiring + Key Vault secrets
├── variables.tf           # Input variables with defaults and docs
├── locals.tf              # Naming helpers
├── outputs.tf             # Connection details for operators and CI
├── moved.tf               # State moves for the monolith -> modules refactor
├── providers.tf / versions.tf  # Providers + remote azurerm backend declaration
├── modules/               # network, compute, database, automation, storage, keyvault
├── .github/workflows/     # pr-validation.yml, security-scan.yml, deploy-from-sync.yml
├── scripts/tfvars_meta.py # Utility used by CI to read tfvars metadata
├── .trivyignore           # Accepted security-scan baseline
├── terraform.tfvars.example
├── README.md
└── AUTOMATION.md
```
