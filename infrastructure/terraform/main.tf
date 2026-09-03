# ==========================================
# Data Sources
# ==========================================
# Fetch the existing resource group we created earlier
data "azurerm_resource_group" "rg" {
  name = "rg-telemetry-dev"
}

# ==========================================
# Azure Databricks (Minimum Cost PoC)
# ==========================================
resource "azurerm_databricks_workspace" "databricks" {
  name                        = "dbw-telemetry-poc"
  resource_group_name         = data.azurerm_resource_group.rg.name
  location                    = data.azurerm_resource_group.rg.location
  
  # Standard SKU is the cheapest tier (no premium features required for PoC)
  sku                         = "standard"
  
  tags = {
    Environment = "PoC"
    CostCenter  = "Minimum"
  }
}

# ==========================================
# Snowflake (Minimum Cost PoC)
# ==========================================
# Note: The Snowflake provider requires credentials (SNOWFLAKE_USER, SNOWFLAKE_PASSWORD, SNOWFLAKE_ACCOUNT)
# to be set as environment variables during execution.

resource "snowflake_database" "telemetry_db" {
  name    = "TELEMETRY_POC_DB"
  comment = "Database for telemetry PoC data"
}

resource "snowflake_schema" "telemetry_schema" {
  database = snowflake_database.telemetry_db.name
  name     = "RAW_DATA"
  comment  = "Schema for raw incoming JSON telemetry"
}

resource "snowflake_warehouse" "telemetry_wh" {
  name           = "TELEMETRY_POC_WH"
  comment        = "Warehouse for telemetry PoC processing"
  
  # X-Small is the smallest, cheapest compute size
  warehouse_size = "X-SMALL"
  
  # Crucial for PoC cost savings: Suspend the warehouse automatically after 1 minute of inactivity
  auto_suspend   = 60
  
  # Don't keep it running if there are no queries
  auto_resume    = true
  
  # Min/Max clusters set to 1 to prevent automatic scaling costs
  min_cluster_count = 1
  max_cluster_count = 1
}
