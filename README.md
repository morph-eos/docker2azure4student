# Terraform blueprint for the student-friendly Azure stack

This repository contains the Terraform code that stands up a small Azure footprint tailored for Azure for Students subscriptions: one Linux VM that runs your containerized workload and a managed PostgreSQL Flexible Server, surrounded by automation to keep costs predictable and provide self-service backups.

## Architecture overview

Resources are deployed inside a single resource group whose name is derived from `environment_name` (normalized and truncated to 45 characters):

- **Networking** – A /16 virtual network with one subnet dedicated to the VM. The NSG keeps HTTP/HTTPS open and limits SSH to the CIDR list declared in `allowed_admin_cidrs`.
- **Compute** – An Ubuntu 22.04 LTS VM (`azurerm_linux_virtual_machine.app`) with a 64 GB Premium SSD OS disk. Only SSH keys are accepted; password auth stays disabled.
- **Public ingress** – A basic SKU public IP (dynamic by default, switchable to static) and a NIC wired to the VM subnet.
- **Automation** – An Azure Automation account is created only when at least one automation feature is enabled. Runbooks handle VM start/stop schedules, ad-hoc snapshots, snapshot cleanup, and PostgreSQL manual backups.
- **Database** – Azure Database for PostgreSQL Flexible Server using the Basic B1ms SKU. Storage is set to 32 GB and `db_auto_grow_enabled = false` by default to stay within the free tier. Terraform also creates the default database (`postgres`) plus firewall rules for Azure services and (optionally) the VM public IP.
- **Blob storage** – An Azure Storage Account (Standard LRS, TLS 1.2 only) is created only when `blob_storage_enabled = true`. Public blob access is disabled by default. The account name and primary key are exposed as outputs and added to the application environment as `AZURE_ACCOUNT_NAME` and `AZURE_ACCOUNT_KEY`.
- **Convenience outputs** – SSH command, VM IP, PostgreSQL connection strings, and (when enabled) the storage account name are exported so application teams do not need to hunt for them in the portal.

## Remote state

Terraform state is stored remotely in Azure Storage so that it survives ephemeral CI runners, is shared across machines, and is protected against concurrent writes (the `azurerm` backend takes a blob lease, which stops two `terraform apply` runs from corrupting the state at the same time).

The backend is **bootstrapped automatically by the pipeline** — there is no manual setup and no extra file or secret to maintain:

- `versions.tf` declares an empty `backend "azurerm" {}`; the concrete settings are injected at `init` time via `-backend-config`.
- On every run the workflow ensures the backing resources exist (create-if-missing, fully idempotent):
  - **Resource group** `tfstate-rg`
  - **Storage account** named `<environment_name><suffix>`, where the suffix is derived deterministically from the subscription ID (the name stays globally unique yet stable across runs)
  - **Container** `tfstate`, with the state stored under the key `docker2azure.tfstate`
- The storage account is created with **blob versioning** and **soft delete** (7 days) enabled, so a bad apply can be recovered.

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
| VM daily schedule | `vm_schedule_enabled`, `vm_schedule_start_time`, `vm_schedule_stop_time`, `vm_schedule_timezone` | Creates Automation runbooks + schedules that start and stop the VM every day to save credits. |
| Manual VM snapshot | `vm_snapshot_runbook_enabled` | Deploys the `*-snapshot` runbook so you can trigger OS disk snapshots on demand without a Recovery Services vault. |
| Snapshot cleanup | `vm_snapshot_cleanup_enabled`, `vm_snapshot_retention_days`, `vm_snapshot_cleanup_time`, `vm_snapshot_cleanup_timezone` | Schedules a cleanup runbook that deletes snapshots older than your retention window. |
| PostgreSQL on-demand backup | `db_backup_enabled`, `db_backup_time`, `db_backup_timezone` | Adds a runbook + schedule that calls the Flexible Server REST API to create an extra backup once per day. |

Set the boolean flags to `false` when you do not need a capability; Terraform will skip the related Automation modules, runbooks, schedules, and job bindings.

## Prerequisites

- Terraform >= 1.5 and the Azure CLI installed locally.
- An Azure subscription where you can create a service principal or use your CLI session (`az login`).
- An SSH public key (ed25519 or RSA) that will become the only authentication method for the VM.
- Optional: Docker and jq if you want to reproduce the GitHub Actions workflow locally.

## Configure variables

1. Copy the template and adjust the values:

   ```bash
   cd /home/morph-eos/Codice/docker2azure4student
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` and provide:
   - `subscription_id` / `tenant_id` when you are not relying on the logged-in Azure CLI identity.
   - `environment_name`, `location`, and your SSH public key (`admin_ssh_public_key`).
   - Database credentials (`db_admin_username`, `db_admin_password`).
   - Any CIDR ranges that should reach the VM via SSH/HTTP/HTTPS.

3. Whenever a pipeline needs to read a subset of values (subscription ID, environment name, etc.), run the helper script:

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

Terraform will provision every resource listed above. Use `terraform destroy` when you no longer need the environment (remember to export database data beforehand).

## Outputs and what to do with them

- `resource_group_name` – Use it to scope Azure CLI commands after deployment.
- `vm_public_ip` / `ssh_connection_string` – Connect to the VM and install runtime dependencies (Docker, certbot, etc.).
- `database_fqdn` / `database_connection_string` – Configure your application or connection pools. The connection string uses TLS (`sslmode=require`).
- `storage_account_name` / `storage_account_key` – Available only when `blob_storage_enabled = true`. The CI workflow automatically injects these as `AZURE_ACCOUNT_NAME` and `AZURE_ACCOUNT_KEY` into the application `.env` file.

## Day-2 operations

- **First login** – SSH into the VM, install Docker, and add your user to the `docker` group. The GitHub workflow can perform these steps automatically, but doing it once manually is useful during bring-up.
- **Snapshots** – Open the Automation account, run the `*-snapshot` runbook, and provide the resource group plus VM name. Names are prefixed with `manual-<timestamp>` by default.
- **Cleanup** – When enabled, the `*-snapshot-cleanup` runbook runs daily and deletes snapshots older than `vm_snapshot_retention_days`. You can run it manually as well.
- **Database backups** – Terraform configures platform backups (PITR) through `backup_retention_days`. Enabling the custom backup runbook gives you an extra manual restore point without touching the portal.
- **Firewall adjustments** – Update `allowed_admin_cidrs` and reapply Terraform whenever admins rotate networks. If you switch to a static public IP, Terraform will automatically add the database firewall rule that matches it.

## GitHub Actions integration (high level)

### Branch, pull request, and documentation workflow

This repository is treated as a fork/reference for the Locus platform. Prefer reading it and using it as infrastructure guidance; avoid modifying it unless the task explicitly requires infrastructure changes here.

For explicit infrastructure work in this repo, committing and pushing directly to `main` is acceptable when the change is scoped and verified. Pull requests may still trigger repository checks, and the `sync/...` branches used by deployment automation are temporary delivery branches, not feature branches.

Before any important infrastructure or architecture change, update the affected README or `.md` files. This includes Terraform variables, deployment flow, required secrets, rollback expectations, and operational runbooks.

### Pull request validation

Every pull request targeting `main` runs `.github/workflows/pr-validation.yml`, which gives fast feedback before code is merged:

1. `terraform fmt -check` and `terraform validate` always run (no cloud credentials required).
2. When Azure credentials are available, it also runs `terraform plan` against the live remote state.
3. The validation output (and the plan, when produced) is published as a build artifact.

When branch protection is enabled on `main`, merging requires the validation check to pass, at least one approving review, and signed commits, while force-pushes are disabled.

### Continuous deployment

The workflow at `.github/workflows/deploy-from-sync.yml` expects a short-lived branch named `sync/...` that contains a `sync-bundle/` directory with your application artifacts and Dockerfile. During CI the workflow:

1. Recreates `terraform.tfvars` from the `TFVARS_B64` secret.
2. Ensures the remote state backend exists — the resource group, storage account, and container are created on the first run and reused afterwards, with no backend file or secret to manage — then runs `terraform apply`.
3. Builds and pushes a container image using the bundle provided by the private application repository.
4. Copies the `.env` file derived from `APP_ENV_VARS_B64` to the VM, then redeploys the container via Docker over SSH.
5. Always deletes the temporary NSG rule and the `sync/...` branch when it finishes.

Refer to `AUTOMATION.md` for the full automation playbook, including every required secret and how the two repositories (private app vs public infra) coordinate.

> **Tip:** Clone this repository into your own private workspace (or fork it privately) before wiring up secrets. That way you keep infrastructure code readable for collaborators while preventing strangers from inspecting your workflow runs or deployment metadata.

## Repository layout

```text
.
├── main.tf                # Azure resources (RG, VNet, VM, Automation, PostgreSQL, Storage)
├── variables.tf           # Input variables with defaults and docs
├── locals.tf              # Naming helpers + schedule timestamps
├── outputs.tf             # Connection details for operators and CI
├── providers.tf / versions.tf  # Providers + remote azurerm backend declaration
├── .github/workflows/     # pr-validation.yml (CI) and deploy-from-sync.yml (CD)
├── scripts/tfvars_meta.py # Utility used by CI to read tfvars metadata
├── terraform.tfvars.example
├── README.md
└── AUTOMATION.md
```

Use this repo as the public-facing IaC source while keeping your application code private; the GitHub workflow handles the hand-off between the two worlds.
