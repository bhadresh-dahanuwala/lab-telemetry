terraform {
  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.0"
    }
    snowflake = {
      source  = "Snowflake-Labs/snowflake"
      version = "~> 0.86"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-telemetry-dev"
    storage_account_name = "sttfstateozjr7qenbbjhm"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
  }
}
