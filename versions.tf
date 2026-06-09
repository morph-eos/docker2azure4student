terraform {
  required_version = ">= 1.5.0"

  # Remote state on Azure Storage. The concrete settings (resource group,
  # storage account, container, key) are injected at init time by the
  # pipeline via -backend-config, so nothing environment-specific is
  # hardcoded here and no extra file/secret is required.
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}
