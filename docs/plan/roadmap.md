# Project Roadmap: Telemetry Data Pipeline

This document outlines the step-by-step implementation plan for the telemetry data ingestion pipeline using Azure, Databricks, and Snowflake.

## Phase 1: Foundation & State Management
**Goal:** Establish the foundational Azure resources required to manage Infrastructure as Code (IaC) state.
*   [x] Write Bicep template for the core Azure Resource Group (Completed).
*   [x] Write Bicep template for an Azure Storage Account and Blob Container.
*   [x] Configure Terraform remote backend (`backend "azurerm"`) to point to the newly created Storage Account.
*   *(Note: GitHub OIDC authentication is already configured)*

## Phase 2: Core Azure Infrastructure (Bicep)
**Goal:** Provision the data ingestion and routing layer in Azure.
*   [x] **Azure Data Lake Storage (ADLS v2):** Create the storage account with hierarchical namespace enabled to store raw incoming JSON data (Bronze layer).
*   [x] **Azure Event Hub:** Provision the Event Hub namespace and topic(s) for streaming data to downstream consumers.
*   [x] **Function Hosting:** Provision the Azure Functions App (compute resource) and its associated Storage Account.
*   [x] Configure Managed Identities / Role-Based Access Control (RBAC) so the API can securely write to ADLS v2 and Event Hub.

## Phase 3: Analytics Infrastructure (Terraform)
**Goal:** Provision the downstream data platforms to consume the Event Hub streams.
*   [ ] **Databricks:** Write Terraform code to provision the Databricks Workspace.
*   [ ] **Snowflake:** Write Terraform code to provision Snowflake resources (Databases, Schemas, Warehouses).
*   [ ] Set up integration points (e.g., configuring Databricks and Snowflake to ingest from the Azure Event Hub).

## Phase 4: Azure Function Development
**Goal:** Build the serverless application that receives telemetry data from users.
*   [ ] Initialize the Azure Functions project (Python).
*   [ ] Implement the POST endpoint to receive JSON telemetry payloads.
*   [ ] Implement logic to save the raw JSON to ADLS v2.
*   [ ] Implement logic to publish the JSON message to Azure Event Hub.
*   [ ] Add unit tests and configuration management.

## Phase 5: CI/CD Pipeline (GitHub Actions)
**Goal:** Automate the deployment of both infrastructure and application code.
*   [ ] Create `.github/workflows/infra-azure.yml`: Automate Bicep deployments to Azure using OIDC.
*   [ ] Create `.github/workflows/infra-data.yml`: Automate `terraform plan` and `terraform apply` for Databricks and Snowflake.
*   [ ] Create `.github/workflows/func-deploy.yml`: Automate the build, test, and deployment of the Azure Function code to the Azure host.
