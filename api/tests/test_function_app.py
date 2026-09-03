import pytest
import azure.functions as func
import json
import os
import sys
from unittest.mock import MagicMock, patch

# Add the current directory to sys.path so it can find function_app.py
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Set dummy environment variables so the global producer doesn't fail on import
os.environ["EVENTHUB_NAMESPACE_FQDN"] = "dummy.servicebus.windows.net"
os.environ["EVENTHUB_NAME"] = "dummy"

# Import the function app module after setting env vars
import function_app

def test_telemetry_ingest_valid_json():
    """
    Test that a valid JSON payload is successfully parsed,
    added to an Event Hub batch, and sent.
    """
    # Arrange: Create a mock HTTP POST request with valid JSON
    req = func.HttpRequest(
        method='POST',
        url='/api/telemetry',
        body=json.dumps({"sensor_id": "ABC-123", "temperature": 22.5}).encode('utf8')
    )
    
    # Arrange: Mock the global Event Hub producer and batch
    mock_producer = MagicMock()
    mock_batch = MagicMock()
    mock_producer.create_batch.return_value = mock_batch
    
    # Temporarily replace the global producer in the function app module
    original_producer = function_app.producer
    function_app.producer = mock_producer
    
    try:
        # Act: Call the function directly
        resp = function_app.telemetry_ingest(req)
        
        # Assert: Check HTTP response
        assert resp.status_code == 202
        assert resp.get_body() == b"Telemetry successfully ingested."
        
        # Assert: Check that Event Hub SDK methods were called correctly
        mock_producer.create_batch.assert_called_once()
        mock_batch.add.assert_called_once()
        mock_producer.send_batch.assert_called_once_with(mock_batch)
    finally:
        # Restore the original producer for subsequent tests
        function_app.producer = original_producer

def test_telemetry_ingest_invalid_json():
    """
    Test that an invalid JSON payload returns a 400 Bad Request.
    """
    # Arrange: Create a request with malformed JSON
    req = func.HttpRequest(
        method='POST',
        url='/api/telemetry',
        body=b"This is not a JSON object"
    )
    
    # Act
    resp = function_app.telemetry_ingest(req)
    
    # Assert
    assert resp.status_code == 400
    assert resp.get_body() == b"Invalid JSON payload."

def test_telemetry_ingest_uninitialized_producer():
    """
    Test that the API returns a 500 error if the Event Hub client
    failed to initialize (e.g., missing configuration).
    """
    # Arrange: Valid request
    req = func.HttpRequest(
        method='POST',
        url='/api/telemetry',
        body=json.dumps({"sensor": "test"}).encode('utf8')
    )
    
    # Arrange: Simulate missing/failed producer
    original_producer = function_app.producer
    function_app.producer = None
    
    try:
        # Act
        resp = function_app.telemetry_ingest(req)
        
        # Assert
        assert resp.status_code == 500
        assert resp.get_body() == b"Event Hub client is not initialized. Check server configuration."
    finally:
        function_app.producer = original_producer

def test_telemetry_ingest_eventhub_exception():
    """
    Test that if the Event Hub client throws an exception during send,
    the API catches it and returns a 500 error.
    """
    # Arrange
    req = func.HttpRequest(
        method='POST',
        url='/api/telemetry',
        body=json.dumps({"sensor": "test"}).encode('utf8')
    )
    
    mock_producer = MagicMock()
    # Force the send_batch method to raise an Exception
    mock_producer.send_batch.side_effect = Exception("Simulated network timeout")
    
    original_producer = function_app.producer
    function_app.producer = mock_producer
    
    try:
        # Act
        resp = function_app.telemetry_ingest(req)
        
        # Assert
        assert resp.status_code == 500
        assert resp.get_body() == b"Internal server error while processing telemetry."
    finally:
        function_app.producer = original_producer
