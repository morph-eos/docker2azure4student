# Using docker2azure4student without cloning or forking it

You do not copy this repository. Your own **private** repository holds only what is yours (secrets, settings, two short workflow files) and **calls** the deploy and rollback workflows of this one, at a version you choose. A change to the template reaches you by changing that version, not by merging code.

```
your application repo ──pushes a bundle──▶ sync/<run>-<sha> branch of YOUR private repo
                                                   │ (push triggers YOUR caller workflow)
                                                   ▼
                       docker2azure4student/.github/workflows/deploy-from-sync.yml@v1   (this repository, public)
                          · checks out the Terraform and scripts of this repository at that version
                          · checks out your bundle from your sync/ branch
                          · signs in to Azure by OIDC as YOUR repository, applies, deploys the container
```

## What you need
- An Azure subscription (the Terraform targets Azure for Students) and rights to create an app registration with a federated credential.
- A **private** GitHub repository for the deployment (say `my-deploy`). GitHub Pro (free for students) gives you rulesets on private repositories; without it some of the protections below are not available.
- An application repository whose pipeline builds a bundle (`sync-bundle/` with a `Dockerfile` and `manifest.json`) and pushes it to a branch `sync/<run-id>-<short-sha>` of `my-deploy`. Preferably with a GitHub App's short-lived token, not a personal token ([AUTOMATION.md](AUTOMATION.md), workflow A).

## Set it up
1. **The two callers.** In `my-deploy`, copy [`examples/caller-deploy.yml`](examples/caller-deploy.yml) to `.github/workflows/deploy-from-sync.yml` and [`examples/caller-rollback.yml`](examples/caller-rollback.yml) to `.github/workflows/rollback.yml`. The part after `@` is the version of the template (below). Nothing else of this repository is needed in `my-deploy`.
2. **Azure.** Create the app registration of the deploy identity and give it a *federated credential* for your repository and the environment `production`: subject `repo:<owner>/my-deploy:environment:production` (check the exact subject of your account in a run's token; accounts with a customised subject differ). Grant it *Contributor* on the subscription, and see the README (*Authentication*) for the rest.
3. **Environment.** In `my-deploy`: Settings, Environments, create `production`.
4. **Variables** (Settings, Secrets and variables, Actions, Variables): `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`. Optional: `DEPLOY_PUSH_ACTOR` (the login of the bot that pushes the bundles, `<app-slug>[bot]`: a push to `sync/**` by anyone else does not deploy), `VM_HOST_KEY` (the VM's host key line from `ssh-keyscan -t ed25519 <ip>`, taken once from a trusted network: SSH then checks the VM against it), `AZURE_PLAN_CLIENT_ID`.
5. **Secrets** (same page, Secrets, **repository** secrets): `TFVARS_B64` (the whole `terraform.tfvars`, base64 on one line), `IMAGE_REGISTRY`, `IMAGE_NAME`, `REGISTRY_LOGIN_SERVER`, `CONTAINER_REGISTRY_USERNAME`, `CONTAINER_REGISTRY_PASSWORD`, `VM_SSH_USERNAME`, `VM_SSH_KEY`, and optionally `APP_ENV_VARS_B64`. What each one is: [AUTOMATION.md](AUTOMATION.md), *Required secrets*.
6. **First deploy.** Push a bundle branch from the application pipeline, or run the *Deploy from sync bundle* workflow by hand with the name of an existing `sync/...` branch. A rollback in *preview* mode (the `apply` switch off) is a safe first test of the credentials.

## Versions
The template is released with tags. `v1.0.0` is an immutable release; `v1` moves to the newest `v1.x.y` (compatible changes only); a commit SHA freezes the exact code. Put the one you want after `@` in both callers:

| After `@` | You get | Use it when |
|---|---|---|
| `v1` | every compatible update, at your next deploy | you trust the template's maintainer and want the fixes |
| `v1.0.0` | exactly that release | you want to read the changes before taking them |
| a full commit SHA | exactly that code, even if a tag is moved | the deployment is critical or audited |

To update: change the version in the two callers, in a pull request of one line, and read the release notes first. The terraform rollback takes its `git_ref` from the **template** (a tag or commit of this repository), so a rollback to "the infrastructure of v1.0.0" is a one-word input.

## How it works
- The called workflow runs **in your repository's context**: `vars`, the environment, the concurrency group and the OIDC subject are yours, so the Azure credential is bound to your repository, not to this one.
- The workflow needs the template's own Terraform and scripts, but the `github` context does not say which commit of this repository it was called at. It reads that from the claims of its OIDC token (`job_workflow_ref` and `job_workflow_sha`) and checks that exact commit out: you always run the Terraform that belongs to the workflow version you chose.
- Only the secrets you list in the caller reach the called workflow (the caller's environment secrets do not: tested). That is why the secrets are repository secrets, and why the caller lists them by name.
- The bundle is taken from the `sync/...` branch of your repository, the same branch that triggered the run. The workflow refuses a branch whose name is not `sync/<letters, digits, . _ ->`, deletes the bundle branch when it ends, and removes the temporary SSH rule even on failure.

## Security: what to set and what you trust
- **You trust the version of the template you call.** It runs with your Azure access. Take updates deliberately (a tag or a SHA), and treat this repository's `main` as the supply chain of your deployment. `main` here requires a pull request and passing checks, with no bypass.
- **Who can start a deployment** is decided in your repository: a ruleset on `refs/heads/sync/**` with *creation*, *update* and *non fast forward*, and your deploy bot as the only bypass actor; plus `DEPLOY_PUSH_ACTOR`. Without a ruleset (a free organization) the variable is the only guard, and anyone with write access can still change the caller workflow.
- **A ruleset on `main`** of your repository: pull request required, no bypass. There is little to review (two short files), but it keeps a stolen token from editing the callers.
- Repository secrets are readable by any workflow on any branch of your repository, so keep write access to it small. GitHub gives a *called* workflow no access to environment secrets.
- Third-party actions inside the template are pinned to commit SHAs; set *Require actions to be pinned* in your repository too.

## Upgrading
### From v1 to v2 (Ubuntu 24.04 and azurerm 5)
`v2.0.0` moves the VM from Ubuntu 22.04 to **Ubuntu 24.04 LTS** (supported until 2029; 22.04's standard support ends in 2027) and the Terraform provider from azurerm 3 to **5**. That is why it is a major version: the next deploy **replaces the VM** (a new OS disk). Expect about 8 minutes without the site, and:
- the Let's Encrypt certificate is issued again by the app's entrypoint when the container starts (the DNS name must still point at the VM's static IP, which does not change);
- the VM's SSH host key changes: update `VM_HOST_KEY` if you pinned it;
- the database, the Key Vault, the storage account and the network are untouched; the VM's managed identity is new and its Key Vault access policy is recreated in the same run;
- the deploy workflow takes a **snapshot of the old OS disk** before applying (a notice with its name, and the command to delete it, appears in the run) so that you can recover anything from it. Delete it when you have verified the new VM; it costs a little every month.

Before taking it, run a **preview**: the rollback workflow with `target: terraform`, `git_ref: v2.0.0` and `apply` off prints the plan against your real state without changing anything. It must show the VM and its Key Vault access policy "must be replaced", and nothing else you do not expect. To stay on Ubuntu 22.04 for now set `vm_image` in your `terraform.tfvars` (the commented example in `terraform.tfvars.example`) or stay on `@v1`.

### Changing the operating system image later
`vm_image` is a variable (publisher, offer, sku, version). Changing it always replaces the VM, with the snapshot and the steps above; `version = "latest"` never replaces it by itself, so an existing VM is not touched when Canonical publishes a new build. For the in-place alternative (`do-release-upgrade` on the VM) you would also set `lifecycle { ignore_changes = [source_image_reference] }` on the VM, which this template does not do: a rebuilt VM is what the pipeline knows how to configure from nothing.

## Limits
- One production environment per repository; the callers use the environment named `production`.
- The Terraform plan of pull requests (`pr-validation.yml`) belongs to this repository's own checks; your repository has no Terraform, so there is nothing to plan there. The terraform rollback's preview mode shows a plan on demand.
- Workflow A (building and pushing the bundle) is yours; [AUTOMATION.md](AUTOMATION.md) describes what it has to produce.
