There are the following three platforms involved in this project:

- Azure
- Databricks
- Snowflake

Here is the information about how the data will flow.

1. We will host an API on Azure. The users will send JSON data to this API.
2. The API will store the raw JSON data in ADLS v2 and send it to `Azure Event Hub`.
3. The Databricks and Snowflake will read from the event hub and load the data in their respective tables.

I want to use Terraform for Databricks and Snowflake infrastructure setup.

We need to implement GitHub workflow.