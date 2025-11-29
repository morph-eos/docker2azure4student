# Terraform blueprint for student-friendly Azure deployment

This folder contains an opinionated Terraform setup that provisions everything needed to run a containerized web API plus a managed PostgreSQL database on Azure, keeping the footprint within the Azure for Students free tier limits as much as possible.

## What gets created

- Resource Group scoped to a single region (default: France Central).
- Virtual network with a subnet and a lightweight NSG (HTTP/HTTPS always open, SSH restricted to the CIDRs you provide).
- Public IP, NIC, and a small Ubuntu-based VM (default size `Standard_B1s`) ready to host your containerized workload. The public IP is dynamic by default, but it can be switched to static via `vm_public_ip_static` when you need a stable endpoint.
- VM OS disk fixed at 64 GB Premium SSD P6, which matches the free-tier SKU available in Azure for Students. Increasing the disk size moves you out of the free tier.
- Automation runbook to create on-demand snapshots of the VM OS disk (no Recovery Services vault involved) so you can create restore points when you need them.
- Azure Automation account created only when required, with optional runbooks to start/stop the VM on a schedule and a daily job that automatically removes snapshots older than the configured retention window.
- Azure Database for PostgreSQL Flexible Server on the Basic SKU with backups enabled* and storage sized to stay within the free limits when `db_auto_grow_enabled = false`.
- Automation runbook (optional) that triggers a managed PostgreSQL backup every evening to add an extra safety net on top of point-in-time restore.
- Firewall rules so the VM (when using a static public IP) and Azure services can securely reach the database.
- Opinionated outputs (SSH command, DB connection string, etc.) to simplify hand-off to application teams.

\* You can further shrink costs by pausing the DB or switching to burstable SKUs when available in your region.

## Getting started

1. Authenticate against Azure (Azure CLI is the simplest option):

   ```bash
   az login
   az account set --subscription <your-subscription-id>
   ```

2. Copy the variable template and fill in the blanks (especially secrets such as the DB password and SSH key):

   ```bash
   cd /Users/morpheus/Codice/docker2azure4student
   cp terraform.tfvars.example terraform.tfvars
   ```

3. Review/adapt the defaults in `variables.tf` if needed (e.g., change region, VM size, container image, or open ports).
4. Launch Terraform:

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

5. Once the apply completes, grab the outputs to connect via SSH or configure your application to use the managed database.

## Key variables

| Variable | Purpose |
| --- | --- |
| `environment_name` | Prefix for every Azure resource (no private app names are baked in). |
| `admin_ssh_public_key` | SSH key allowed on the VM; generate one with `ssh-keygen` if you don't have it yet. |
| `vm_http_port` | External HTTP port opened on the VM. HTTPS is controlled through `vm_https_port`. |
| `automation_location` | Region that hosts Azure Automation (defaults to `eastus`, one of the allowed Student-plan regions). |
| `vm_schedule_*` | Toggle and timezone/start/stop times that control the optional daily start/stop schedule for the VM (disabled by default). |
| `vm_public_ip_static` | If `true`, allocates a static public IP; by default a dynamic IP is used to stay within the free tier. |
| `allowed_admin_cidrs` | IPv4 CIDR blocks with SSH access. Leave empty to disable SSH from the internet and rely on privileged Azure Bastion or similar services. |
| `db_admin_*` settings | Credentials + sizing for the PostgreSQL flexible server. |
| `db_storage_mb` / `db_auto_grow_enabled` | Configures the PostgreSQL server storage size (default 32 GB). Keep `db_auto_grow_enabled = false` to remain within the free tier and avoid automatic expansion beyond 32 GB. |
| `db_zone` | Availability zone of the PostgreSQL flexible server (defaults to `1` to match the initial deployment). |
| `vm_snapshot_runbook_enabled` | Deploys the Automation runbook that creates manual snapshots of the VM OS disk instead of relying on Azure Backup. |
| `vm_snapshot_cleanup_enabled` | When `true`, deploys the runbook and schedule that automatically delete snapshots older than `vm_snapshot_retention_days`. |
| `vm_snapshot_retention_days` | Number of days to keep snapshots before they are deleted by the cleanup job (default 90). |
| `vm_snapshot_cleanup_time` / `vm_snapshot_cleanup_timezone` | Time of day and timezone for the daily snapshot cleanup job. |
| `db_backup_*` | Controls the daily Automation job that triggers a managed PostgreSQL backup (set `db_backup_enabled = false` if you only want the default PITR window). |

Check `terraform.tfvars.example` for a quick starting point.

## Operational notes

- After Terraform finishes, SSH into the VM (see `ssh_connection_string` output) and run whatever bootstrap you need (install Docker, configure your container runtime, copy TLS certs, etc.). Keeping this step manual avoids surprises and lets you tailor the host exactly as required.
- Networking stays simple on purpose: no load balancers, no private DNS. Add them once you exceed the free tiers.
- Database firewall, when using a static public IP, restricts access to the VM public IP plus the special `0.0.0.0` rule required for Azure services provisioning. When using a dynamic IP, the dedicated firewall rule is not created and you rely on the "Allow Azure services" rule; in that case consider switching to a static IP or adding specific firewall rules before exposing the database to the internet.
- To stay within the PostgreSQL free tier (750 B1ms hours + 32 GB storage + 32 GB backup), keep `db_auto_grow_enabled = false`, use `db_storage_mb = 32768` or less, and consider stopping the server when not in use.
- Destroying the stack (`terraform destroy`) will delete the database as well—export backups before running it in production-like environments.
- The Automation schedule is optional (disabled by default); the manual snapshot runbook is always available and the daily cleanup job (also optional) automatically deletes snapshots older than the configured retention window.
- To create an OS disk snapshot, open the Automation account, select the `*-snapshot` runbook, click **Start**, and provide `resourceGroupName` and `vmName`. Each snapshot name includes the chosen prefix and a timestamp. The same account hosts the `*-snapshot-cleanup` runbook, which runs on schedule (or on demand) and removes snapshots older than the configured retention window.

### Suggested manual bootstrap (optional)

```bash
# from your laptop
ssh azureuser@<vm_public_ip>

# on the VM
sudo apt update && sudo apt install -y docker.io docker-compose
sudo usermod -aG docker azureuser && newgrp docker

# example: create env file with DB outputs (fill values from terraform output)
cat <<'EOF' > ~/app.env
DATABASE_HOST=<value_from_output>
DATABASE_NAME=appdb
DATABASE_USER=<username@server>
DATABASE_PASSWORD=<your_password>
DATABASE_PORT=5432
EOF

docker run -d --name webapp --restart unless-stopped --env-file ~/app.env -p 80:8080 ghcr.io/your-org/your-api:latest
```

## Repository layout

```text
.
├── main.tf                # End-to-end infrastructure definition
├── variables.tf           # Typed variables with safe defaults
├── locals.tf              # Helper to normalize the naming prefix
├── outputs.tf             # Helpful connection details
├── providers.tf / versions.tf
├── terraform.tfvars.example
├── .gitignore
└── README.md
```

This project is intentionally generic, so you can pair it with any containerized workload without ever exposing private solution names.
