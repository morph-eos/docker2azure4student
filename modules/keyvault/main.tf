resource "azurerm_key_vault" "main" {
  name                       = "${var.name_prefix}-kv"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  tags = merge(var.tags, { component = "security" })
}

# The pipeline service principal is only Contributor, which cannot create RBAC
# role assignments. Access policies are data-plane configuration on the vault
# itself, which Contributor IS allowed to set - so no privilege elevation needed.
resource "azurerm_key_vault_access_policy" "pipeline" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = var.tenant_id
  object_id    = var.pipeline_principal_id

  secret_permissions = ["Get", "List", "Set", "Delete", "Recover"]
}

# NOTE: the VM read access policy is added in a later phase, once the VM's
# system-assigned identity (added in this same change) already exists in state
# and its principal_id is known. Adding it here would be null at plan time.
