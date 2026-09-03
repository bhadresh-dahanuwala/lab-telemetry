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

# ==========================================
# Data Sources for Identity
# ==========================================
data "azurerm_client_config" "current" {}

# ==========================================
# Snowflake Auto-Ingest (Snowpipe)
# ==========================================

# 1. Storage Integration connecting Snowflake to Azure Data Lake
resource "snowflake_storage_integration" "azure_integration" {
  name    = "AZURE_TELEMETRY_INTEGRATION"
  comment = "Integration with Azure Data Lake for Telemetry"
  type    = "EXTERNAL_STAGE"
  
  enabled = true
  storage_provider = "AZURE"
  
  azure_tenant_id  = data.azurerm_client_config.current.tenant_id
  
  # In Phase 5 (CI/CD), we will pass the exact Bicep storage account name as a variable.
  # For now, we allow the known container path.
  storage_allowed_locations = [
    "azure://*/telemetry-bronze/"
  ]
}

# 2. Stage pointing to the Storage Integration
resource "snowflake_stage" "telemetry_stage" {
  name        = "TELEMETRY_AZURE_STAGE"
  database    = snowflake_database.telemetry_db.name
  schema      = snowflake_schema.telemetry_schema.name
  
  url         = "azure://*/telemetry-bronze/"
  storage_integration = snowflake_storage_integration.azure_integration.name
}

# 3. The Pipe (Snowpipe) with auto_ingest enabled
resource "snowflake_pipe" "telemetry_pipe" {
  database = snowflake_database.telemetry_db.name
  schema   = snowflake_schema.telemetry_schema.name
  name     = "TELEMETRY_PIPE"
  
  comment  = "Auto-ingest pipe for Telemetry JSON files"
  
  auto_ingest = true
  
  copy_statement = "COPY INTO ${snowflake_database.telemetry_db.name}.${snowflake_schema.telemetry_schema.name}.RAW_JSON_TABLE FROM @${snowflake_stage.telemetry_stage.name} FILE_FORMAT = (TYPE = JSON)"
}
