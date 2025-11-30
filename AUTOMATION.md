# Automation playbook: dual-repo deployment

This document describes how to connect the private application repository ("App repo") with the public infrastructure repository (`docker2azure4student`) using GitHub Actions. The workflow keeps application code private by syncing it through a short-lived branch in the infra repo and deleting it as soon as the deployment finishes.

## Goals

- Package the private application source, build context, and runtime configuration without disclosing it in the public history of `docker2azure4student`.
- Reuse the Terraform stack already defined in this repo to make sure VM, Automation, and PostgreSQL stay aligned with the Azure for Students footprint.
- Deliver an automated Docker build + VM rollout with zero manual steps once code is merged in the App repo.
- Enforce branch hygiene so each sync branch is removed automatically, keeping the infra repo history clean.

## Repository roles

| Repository | Visibility | Responsibilities |
| --- | --- | --- |
| App repo (private) | Private | Source code, Docker context, runtime secrets (via GitHub Actions secrets). Builds, signs, and transfers sanitized bundles to the infra repo. |
| `docker2azure4student` | Public or internal | Hosts Terraform IaC, deployment scripts, and receives short-lived sync branches that contain the sanitized application bundle. Runs Terraform apply, builds/pushes containers, and deploys to the VM. |

> **Note:** If `docker2azure4student` must stay public and GitHub does not offer private branches for your plan, create a private fork (e.g., `docker2azure4student-sync`) and run the workflow there. The steps below remain unchanged; only the target repo URL differs.

## Workflow A – Private application repository

**Triggers:**

- `push` on `main` (or whichever protected branch you prefer).
- Manual `workflow_dispatch` with an optional reason.

**Secrets required in the application repository:**

| Secret | Purpose |
| --- | --- |
| `INFRA_REPO_PAT` | Fine-scoped PAT (or GitHub App token) with `contents:write` on `M04ph3u2/docker2azure4student` (or the fork you target). |

**What the workflow actually does:**

1. Restores the toolchains declared in the app repo workflow (Node, .NET, etc.), then runs the project-specific tests/build/publish steps.
2. Produces a sanitized bundle under `artifacts/bundle/` containing:
   - `publish/` (self-contained binaries produced by `dotnet publish`).
   - A runtime-only Dockerfile that simply copies the `publish/` folder into `mcr.microsoft.com/dotnet/aspnet:8.0`.
   - `manifest.json` with the source repository, commit SHA, GitHub run ID, and computed image tag (short SHA).
3. Clones the infra repo, checks out its default branch (`main` by default), and creates a short-lived branch named `sync/<run-id>-<short-sha>` that **keeps all the Terraform files** and adds the bundle under `sync-bundle/`.
4. Pushes the branch with only the bundle folder staged (`git add sync-bundle`) so the rest of the repository stays untouched.
5. Cleans local artifacts.

> 📌 Because the branch always builds on top of `main`, Terraform, documentation, and scripts stay available to the infra workflow while your private application source never leaves the app repo.

You can customize the destination repo/branch by editing the `INFRA_REPO`, `INFRA_REPO_DEFAULT_BRANCH`, and `SYNC_BRANCH_PREFIX` env values at the top of the workflow file.

## Workflow B – Infra repo (`docker2azure4student/.github/workflows/deploy-from-sync.yml`)

**Triggers:**

- Automatic `push` to any `sync/**` branch (created by Workflow A).
- Manual `workflow_dispatch` with `sync_branch` input (useful for replays).

**Secrets required in `docker2azure4student`:**

| Secret | Purpose |
| --- | --- |
| `AZURE_CREDENTIALS` | Output of `az ad sp create-for-rbac --name ... --sdk-auth` used by `azure/login@v2` to obtain an access token. |
| `TFVARS_B64` | Base64-encoded `terraform.tfvars` that contains every Terraform variable (subscription/tenant IDs, environment name, SSH key, DB password, etc.). The workflow recreates `terraform.tfvars` from this secret at runtime, so no individual `TF_VAR_*` secrets are required. |
| `TF_BACKEND_CONFIG` *(optional)* | Multiline backend configuration snippet (e.g., `storage_account_name=...`) written to `backend.hcl` when present. Leave empty to keep local state. |
| `IMAGE_REGISTRY` / `IMAGE_NAME` | Registry hostname (including namespace) and repository name used to tag/push the container image. |
| `REGISTRY_LOGIN_SERVER` | Host passed to `docker login` (for GHCR it's `ghcr.io`, for ACR use `<name>.azurecr.io`). |
| `CONTAINER_REGISTRY_USERNAME` / `CONTAINER_REGISTRY_PASSWORD` | Credentials for `docker login` on both the runner (image build) and the VM (image pull). Works with ACR, GHCR, etc. |
| `APP_ENV_VARS_B64` | Base64-encoded `.env` file recreated on the VM before launching the container. |
| `VM_SSH_KEY` | Private SSH key with access to the target VM. |
| `VM_SSH_USERNAME` | Username injected in Terraform outputs and used by the automation to copy files / run commands over SSH. |

### Creating the `TFVARS_B64` secret

1. Start from `terraform.tfvars.example`, create your real `terraform.tfvars`, and keep it **out of version control**.
2. Base64-encode the file without newlines:

   ```bash
   # macOS
   base64 terraform.tfvars | tr -d '\n' | pbcopy

   # Linux
   base64 -w0 terraform.tfvars | xclip -selection clipboard
   ```

   (Replace the clipboard command with whatever is available on your system.)
3. Paste the encoded string into the `TFVARS_B64` secret of the infra repository. Any time you change `terraform.tfvars`, regenerate and update this secret.

**Job outline implemented in `deploy-from-sync.yml`:**

1. **Branch resolution + checkout** – Determines the correct sync branch (payload for manual runs, `github.ref` for pushes) and checks it out so Terraform + `sync-bundle/` files are available.
2. **Terraform** – Logs into Azure, restores `terraform.tfvars` from `TFVARS_B64`, optionally writes `backend.hcl` from `TF_BACKEND_CONFIG`, and runs `terraform init` + `terraform apply -auto-approve`. All Terraform values now come from the reconstructed `terraform.tfvars` file, so no individual `TF_VAR_*` secrets are required.
3. **Outputs** – Reads `vm_public_ip` so we know where to deploy and parses `sync-bundle/manifest.json` to get the image tag.
4. **Container build** – Logs into the registry, builds the runtime image using `sync-bundle/Dockerfile`, tags it as `<IMAGE_REGISTRY>/<IMAGE_NAME>:<imageTag>`, and pushes it.
5. **VM deployment** – Recreates the `.env` file from `APP_ENV_VARS_B64`, copies it over SSH, logs into the registry on the VM, pulls the new image, stops/removes the previous container, and runs the new one (ports `80 -> 8080`, `443 -> 8081`).
6. **Cleanup** – A second job with `if: always()` deletes the sync branch via `actions/github-script` to guarantee that private bundles live only for the duration of the deployment.

> **Container runtime knobs** – The workflow exposes `CONTAINER_SERVICE_NAME`, `CONTAINER_HTTP_PORT`, `CONTAINER_INTERNAL_HTTP_PORT`, `CONTAINER_HTTPS_PORT`, and `CONTAINER_INTERNAL_HTTPS_PORT` as job-level env vars so you can rename the container or remap ports without touching the SSH script. Adjust them directly in `deploy-from-sync.yml` (or via workflow inputs) to match your VM layout.

## Branch privacy workflow

1. **Scoped branches** – Each run creates `sync/<run-id>-<short-sha>` based on the infra repo default branch. The branch only adds the `sync-bundle/` folder, so Terraform and documentation stay intact but no private source code is uploaded.
2. **Minimal exposure** – The bundle contains compiled binaries plus a runtime Dockerfile and manifest. If you need stronger guarantees, encrypt additional artifacts before committing them to `sync-bundle/`.
3. **Automatic deletion** – The `cleanup` job deletes the branch regardless of success/failure (thanks to `if: always()`). Logs keep a trace of what happened without preserving the bundle.
4. **Auditing** – `manifest.json` captures repo, commit, GitHub run ID, and timestamp so you can trace which version produced a deployment.

## Deployment sequence

1. Developer merges to the protected branch (e.g., `main`) in the private application repository (or triggers the workflow manually).
2. Workflow A publishes the .NET backend + Angular app, writes the runtime Dockerfile + manifest inside `sync-bundle/`, and pushes a temporary branch to `docker2azure4student`.
3. The push event automatically starts Workflow B, which keeps infrastructure in sync, builds/pushes the runtime image, and redeploys the VM.
4. Workflow B always deletes the sync branch when it finishes so no bundle lingers in the public history.

## Follow-up items

- Populate every secret listed above (both repos) and rotate them periodically.
- Decide whether to keep the infra repo public; if not, mirror it into a private fork and point `INFRA_REPO` to that remote.
- Connect Terraform to a remote backend (fill `TF_BACKEND_CONFIG`) so pipeline/state stay consistent even when you run `terraform` locally.
- Protect the `deploy-from-sync.yml` workflow with GitHub environments if you need manual approvals or scoped secrets.
- Add smoke tests (HTTP health checks) after deployment before the old container is removed.
