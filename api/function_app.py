import azure.functions as func
import logging
import json
import os
from azure.identity import DefaultAzureCredential
from azure.eventhub import EventHubProducerClient, EventData

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

# Initialize the Event Hub Producer Client globally so it can be reused across invocations.
# In production, DefaultAzureCredential() uses the Managed Identity we created in Bicep.
try:
    fqdn = os.environ.get("EVENTHUB_NAMESPACE_FQDN")
    eventhub_name = os.environ.get("EVENTHUB_NAME")
    
    if fqdn and eventhub_name:
        credential = DefaultAzureCredential()
        producer = EventHubProducerClient(
            fully_qualified_namespace=fqdn,
            eventhub_name=eventhub_name,
            credential=credential
        )
    else:
        logging.warning("Event Hub configuration is missing from Environment Variables.")
        producer = None
except Exception as e:
    logging.error(f"Failed to initialize Event Hub Client: {e}")
    producer = None


@app.route(route="telemetry", methods=["POST"])
def telemetry_ingest(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Received a telemetry POST request.')

    # 1. Parse and validate the JSON payload
    try:
        req_body = req.get_json()
    except ValueError:
        return func.HttpResponse(
             "Invalid JSON payload.",
             status_code=400
        )

    # 2. Check if infrastructure is wired up
    if not producer:
        return func.HttpResponse(
             "Event Hub client is not initialized. Check server configuration.",
             status_code=500
        )

    # 3. Publish to Event Hub
    try:
        event_data_batch = producer.create_batch()
        
        # Convert JSON back to string for Event Hub transmission
        payload_str = json.dumps(req_body)
        event_data_batch.add(EventData(payload_str))
        
        producer.send_batch(event_data_batch)
        
        return func.HttpResponse(
            "Telemetry successfully ingested.",
            status_code=202
        )
    except Exception as e:
        logging.error(f"Error sending telemetry to Event Hub: {e}")
        return func.HttpResponse(
             "Internal server error while processing telemetry.",
             status_code=500
        )
