# Terraform blueprint for student-friendly Azure deployment

This folder contains an opinionated Terraform setup that provisions everything needed to run a containerized web API plus a managed PostgreSQL database on Azure, keeping the footprint within the Student plan limits.

## What gets created

- Resource Group scoped to a single region (default: France Central)
- Virtual network with a subnet and a lightweight NSG (HTTP/HTTPS always open, SSH restricted to the CIDRs you provide)
- Public IP, NIC, and a small Ubuntu-based VM (default size `Standard_B1ms`) ready for you to configure manually (install Docker, agents, etc.)
- The VM OS disk is pinned to a 64 GB Standard SSD (covered by the Azure Free Tier) so you only pay if you grow beyond that footprint
- Optional Recovery Services vault + daily VM backup policy (enabled by default) so you always have rolling restore points without paying extra outside the free tier
- Azure Automation account (only if needed) with schedules to start the VM at 07:00 and stop it at 19:00 so you burn roughly half the compute hours; times/timezone can be changed or disabled via variables
- Azure Database for PostgreSQL Flexible Server on the Basic SKU with backups enabled*
- Automation runbook (optional) that triggers a managed PostgreSQL backup every evening to add an extra safety net on top of point-in-time restore
- Firewall rules so the VM and Azure services can reach the database securely
- Opinionated outputs (SSH command, DB connection string, etc.) to simplify hand-off to application teams

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
| `vm_schedule_*` | Toggle + timezone/start/stop times for the Automation schedule that starts the VM in the morning and shuts it down in the evening. |
| `allowed_admin_cidrs` | IPv4 CIDR blocks with SSH access. Leave empty to disable SSH from the internet and rely on privileged Azure Bastion or similar services. |
| `db_admin_*` settings | Credentials + sizing for the PostgreSQL flexible server. |
| `db_zone` | Availability zone of the PostgreSQL flexible server (defaults to `1` to match the initial deployment). |
| `vm_backup_*` | Enables Azure Backup + retention/timezone knobs for the VM Recovery Services vault policy. |
| `db_backup_*` | Controls the daily Automation job that triggers a managed PostgreSQL backup (set `db_backup_enabled = false` if you only want the default PITR window). |

Check `terraform.tfvars.example` for a quick starting point.

## Operational notes

- After Terraform finishes, SSH into the VM (see `ssh_connection_string` output) and run whatever bootstrap you need (install Docker, configure your container runtime, copy TLS certs, etc.). Keeping this step manual avoids surprises and lets you tailor the host exactly as required.
- Networking stays simple on purpose: no load balancers, no private DNS. Add them once you exceed the free tiers.
- Database firewall currently allows only the VM public IP and the special `0.0.0.0` rule needed for Azure services (required for provisioning). If you need developer laptops to reach the DB directly, create extra firewall rules in Terraform or manually after apply.
- Destroying the stack (`terraform destroy`) will delete the DB as well—export backups before running it in production-like setups.
- The Automation schedules and backup policies are optional; disable them via the tfvars if you plan to keep the VM always-on or prefer handling backups manually.

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
