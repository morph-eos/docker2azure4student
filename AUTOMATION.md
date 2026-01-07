# Automation playbook: app repo ↔ infra repo

This guide explains how the private application repository and this public Terraform repository collaborate to deploy code to Azure without leaking proprietary sources. The flow relies on short-lived `sync/...` branches that carry application artifacts only for the duration of the deployment.

> **Recommendation:** before storing any secrets, create your own private copy of this repository (private fork or mirrored repo). You keep the IaC readable for collaborators while ensuring outsiders cannot inspect workflow runs or deployment metadata.

## Roles & responsibilities

| Repository | Purpose | Key artifacts |
| --- | --- | --- |
| **Private application repo** | Builds and tests the app, produces a sanitized bundle (`sync-bundle/`) with compiled binaries, Dockerfile, and `manifest.json`, and pushes it to a temporary branch inside `docker2azure4student`. | Workflow **A** (maintained in the private repo). |
| **docker2azure4student** | Holds Terraform IaC, automation scripts, and the GitHub Action that provisions Azure resources and redeploys the VM using the received bundle. Cleans up the temporary branch afterwards. | Workflow **B** ([.github/workflows/deploy-from-sync.yml](.github/workflows/deploy-from-sync.yml)). |

Keep this repository public (or internal) to share Terraform modules, but run Workflow A from a private repo so application sources never leave your perimeter.

## Workflow A (private repo) – what to implement

1. Trigger on `push` to the protected branch (usually `main`) and optionally on `workflow_dispatch`.
2. Build/publish the application. The existing environment uses .NET, but the Terraform side is agnostic as long as you produce the right artifacts.
3. Create `sync-bundle/` with at least:
   - `Dockerfile` – Runtime-only Dockerfile that copies the published output into the base image expected by your app (e.g., `mcr.microsoft.com/dotnet/aspnet:8.0`).
   - `manifest.json` – Include `sourceRepo`, `commit`, `imageTag`, and any metadata you want surfaced later.
   - `publish/` (or equivalent) – The files copied by the Dockerfile.
4. Clone `docker2azure4student`, checkout `main`, create a new branch named `sync/<run-id>-<short-sha>`, copy `sync-bundle/` into the repo root, and push.
5. Optionally delete local bundle files to avoid lingering secrets.

> Suggested environment variables: `INFRA_REPO`, `INFRA_REPO_DEFAULT_BRANCH`, `SYNC_BRANCH_PREFIX`, and `INFRA_REPO_PAT` (fine-grained PAT with `contents:write`).

## Workflow B (this repo) – deploy-from-sync.yml

### Triggers

- `push` to any `sync/**` branch (originating from Workflow A).
- `workflow_dispatch` with a `sync_branch` input to redeploy a specific bundle.

### Required secrets

| Secret | Description |
| --- | --- |
| `AZURE_CREDENTIALS` | JSON produced by `az ad sp create-for-rbac --sdk-auth` so `azure/login` can obtain tokens. Scope it to the subscription hosting the Terraform stack. |
| `TFVARS_B64` | Base64 string (no newlines) of the **entire** `terraform.tfvars`. Every Terraform input—including SSH key, DB password, toggles—is read from this file. |
| `TF_BACKEND_CONFIG` *(optional)* | Multiline blob copied to `backend.hcl` before `terraform init`. Use it to point Terraform to remote state (e.g., Azure Storage). Leave empty to keep local state. |
| `IMAGE_REGISTRY` / `IMAGE_NAME` | Registry namespace + repository used in the `docker build` step (for GHCR: `ghcr.io/<org>` and `<repo>`). |
| `REGISTRY_LOGIN_SERVER` | Host passed to `docker login` (e.g., `ghcr.io` or `<acr>.azurecr.io`). |
| `CONTAINER_REGISTRY_USERNAME` / `CONTAINER_REGISTRY_PASSWORD` | Credentials valid both on the GitHub runner and on the VM (used during `docker login` inside SSH). |
| `APP_ENV_VARS_B64` | Base64 string for the `.env` file copied to the VM (contains app runtime secrets). |
| `VM_SSH_USERNAME` | Linux username created on the VM (matches `var.vm_admin_username`). |
| `VM_SSH_KEY` | Private key able to log into the VM (the corresponding public key is stored in Terraform). |

### Creating TFVARS_B64 and APP_ENV_VARS_B64

```bash
# terraform.tfvars
base64 -w0 terraform.tfvars > TFVARS.b64

# application env file
base64 -w0 app.env > APP_ENV_VARS.b64
```

On macOS replace `-w0` with `| tr -d '\n'`. Paste the resulting strings into their respective secrets. Recreate them whenever the source files change.

### Job breakdown

1. **Resolve branch and checkout** – `sync-branch` step detects the branch to deploy (from the push ref or `workflow_dispatch` input) and `actions/checkout` grabs its files.
2. **Restore configuration** – `terraform.tfvars` is reconstructed from `TFVARS_B64`. If `TF_BACKEND_CONFIG` is provided, the workflow writes it to `backend.hcl` and passes `-backend-config=backend.hcl` to `terraform init`.
3. **Terraform plan/apply** – `hashicorp/setup-terraform` installs Terraform, the workflow logs into Azure via `azure/login`, and `terraform apply -auto-approve` provisions/updates the stack. Before applying, the script `scripts/tfvars_meta.py` extracts metadata (subscription ID, environment name, flags) used to import existing resources when needed.
4. **Outputs + NSG window** – The pipeline reads `vm_public_ip` and `database_fqdn`. It temporarily adds an NSG rule (`gha-temp-<run-id>`) that allows SSH from the runner so Docker commands can be executed remotely; the rule is deleted at the end regardless of success.
5. **Build & push image** – The runner logs into the container registry, builds `sync-bundle/Dockerfile`, tags the image as `${IMAGE_REGISTRY}/${IMAGE_NAME}:${imageTag}`, and pushes it.
6. **Prepare runtime secrets** – `APP_ENV_VARS_B64` is decoded into `app.env`. The workflow appends a `POSTGRES_CONNECTION_STRING` (built from Terraform outputs) so the container can reach the managed database.
7. **SSH deployment** – Using the provided private key, the workflow ensures Docker is installed on the VM, copies `app.env`, logs into the same registry from the VM, pulls the new image, and runs it as `${CONTAINER_SERVICE_NAME}` mapping ports `80->8080` and `443->8081`. `/etc/letsencrypt` is bind-mounted so certificates survive container restarts.
8. **Cleanup** – The temporary NSG rule is deleted even on failure. A dedicated `cleanup` job removes the `sync/...` branch via `actions/github-script` so bundles never linger in the public history.

### Runtime environment variables

Inside `deploy` job you can tune:

- `CONTAINER_SERVICE_NAME` (default `app-service`).
- `CONTAINER_HTTP_PORT` / `CONTAINER_INTERNAL_HTTP_PORT` (default `80/8080`).
- `CONTAINER_HTTPS_PORT` / `CONTAINER_INTERNAL_HTTPS_PORT` (default `443/8081`).

Modify them in the workflow file if your VM exposes different ports or if you run multiple containers side by side.

## Branch hygiene & auditing

1. Workflow A always pushes bundles into `sync/<timestamp>-<short-sha>` built off the `main` branch of this repo. Terraform files remain untouched in the branch, so reviewers can inspect the diff confidently.
2. Workflow B deletes the branch in the `cleanup` job (`if: always()`). Even failed deployments remove the bundle so sensitive artifacts never linger.
3. Every bundle must include `manifest.json` with at least `imageTag` or the workflow falls back to the commit SHA as image tag. Keep `sourceRepo`, `commit`, and `runId` fields to trace deployments end-to-end.

## Recommended hardening

- Store secrets in GitHub Environments with required reviewers for production subscriptions.
- Configure a remote backend (`TF_BACKEND_CONFIG`) so CLI users and CI share the same Terraform state.
- Rotate PATs, registry credentials, and app secrets frequently; automate via GitHub Actions OIDC + Azure Federated Credentials when possible.
- Add post-deploy smoke tests (curl health check, database migrations) before the workflow tears down the previous container.
- Monitor the Automation account runbooks (snapshot, cleanup, VM schedule, DB backup) through alerts so missed jobs are detected early.

Following this playbook keeps private code in its original repository, ensures Terraform stays the single source of truth, and automates VM deployments with minimal manual intervention.
