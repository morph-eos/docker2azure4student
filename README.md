# Terraform blueprint for the student-friendly Azure stack

This repository contains the Terraform code that stands up a small Azure footprint tailored for Azure for Students subscriptions: one Linux VM that runs your containerized workload and a managed PostgreSQL Flexible Server, surrounded by automation to keep costs predictable and provide self-service backups.

## Architecture overview

Resources are deployed inside a single resource group whose name is derived from `environment_name` (normalized and truncated to 45 characters):

- **Networking** – A /16 virtual network with one subnet dedicated to the VM. The NSG keeps HTTP/HTTPS open and limits SSH to the CIDR list declared in `allowed_admin_cidrs`.
- **Compute** – An Ubuntu 22.04 LTS VM (`azurerm_linux_virtual_machine.app`) with a 64 GB Premium SSD OS disk. Only SSH keys are accepted; password auth stays disabled.
- **Public ingress** – A basic SKU public IP (dynamic by default, switchable to static) and a NIC wired to the VM subnet.
- **Automation** – An Azure Automation account is created only when at least one automation feature is enabled. Runbooks handle VM start/stop schedules, ad-hoc snapshots, snapshot cleanup, and PostgreSQL manual backups.
- **Database** – Azure Database for PostgreSQL Flexible Server using the Basic B1ms SKU. Storage is set to 32 GB and `db_auto_grow_enabled = false` by default to stay within the free tier. Terraform also creates the default database (`postgres`) plus firewall rules for Azure services and (optionally) the VM public IP.
- **Convenience outputs** – SSH command, VM IP, and PostgreSQL connection strings are exported so application teams do not need to hunt for them in the portal.

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

terraform init
terraform plan
terraform apply
```

Terraform will provision every resource listed above. Use `terraform destroy` when you no longer need the environment (remember to export database data beforehand).

## Outputs and what to do with them

- `resource_group_name` – Use it to scope Azure CLI commands after deployment.
- `vm_public_ip` / `ssh_connection_string` – Connect to the VM and install runtime dependencies (Docker, certbot, etc.).
- `database_fqdn` / `database_connection_string` – Configure your application or connection pools. The connection string uses TLS (`sslmode=require`).

## Day-2 operations

- **First login** – SSH into the VM, install Docker, and add your user to the `docker` group. The GitHub workflow can perform these steps automatically, but doing it once manually is useful during bring-up.
- **Snapshots** – Open the Automation account, run the `*-snapshot` runbook, and provide the resource group plus VM name. Names are prefixed with `manual-<timestamp>` by default.
- **Cleanup** – When enabled, the `*-snapshot-cleanup` runbook runs daily and deletes snapshots older than `vm_snapshot_retention_days`. You can run it manually as well.
- **Database backups** – Terraform configures platform backups (PITR) through `backup_retention_days`. Enabling the custom backup runbook gives you an extra manual restore point without touching the portal.
- **Firewall adjustments** – Update `allowed_admin_cidrs` and reapply Terraform whenever admins rotate networks. If you switch to a static public IP, Terraform will automatically add the database firewall rule that matches it.

## GitHub Actions integration (high level)

The workflow at `.github/workflows/deploy-from-sync.yml` expects a short-lived branch named `sync/...` that contains a `sync-bundle/` directory with your application artifacts and Dockerfile. During CI the workflow:

1. Recreates `terraform.tfvars` from the `TFVARS_B64` secret and runs `terraform apply`.
2. Builds and pushes a container image using the bundle provided by the private application repository.
3. Copies the `.env` file derived from `APP_ENV_VARS_B64` to the VM, then redeploys the container via Docker over SSH.
4. Always deletes the temporary NSG rule and the `sync/...` branch when it finishes.

Refer to `AUTOMATION.md` for the full automation playbook, including every required secret and how the two repositories (private app vs public infra) coordinate.

> **Tip:** Clone this repository into your own private workspace (or fork it privately) before wiring up secrets. That way you keep infrastructure code readable for collaborators while preventing strangers from inspecting your workflow runs or deployment metadata.

## Repository layout

```text
.
├── main.tf                # Azure resources (RG, VNet, VM, Automation, PostgreSQL)
├── variables.tf           # Input variables with defaults and docs
├── locals.tf              # Naming helpers + schedule timestamps
├── outputs.tf             # Connection details for operators and CI
├── providers.tf / versions.tf
├── scripts/tfvars_meta.py # Utility used by CI to read tfvars metadata
├── terraform.tfvars.example
├── README.md
└── AUTOMATION.md
```

Use this repo as the public-facing IaC source while keeping your application code private; the GitHub workflow handles the hand-off between the two worlds.
