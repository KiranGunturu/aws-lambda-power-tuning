"""
LambdaFunctionOverHttps

A small DynamoDB CRUD handler behind Amazon API Gateway (REST API, non-proxy
Lambda integration). The request body selects the operation:

    {
        "operation": "create" | "read" | "update" | "delete" | "list" | "echo" | "ping",
        "tableName": "lambda-apigateway",      # optional, must match TABLE_NAME
        "payload": { ... }                       # arguments for the DynamoDB call
    }

Design notes
- The boto3 resource and table handle are created once, outside the handler,
  so warm invocations reuse the connection (cheaper and faster).
- The function only ever touches the table named in the TABLE_NAME environment
  variable. A caller cannot point it at another table, even if the IAM role
  were broadened later.
"""

import json
import logging
import os
from decimal import Decimal

import boto3
from botocore.exceptions import ClientError

LOG = logging.getLogger()
LOG.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

TABLE_NAME = os.environ["TABLE_NAME"]
MAX_LIST_ITEMS = int(os.environ.get("MAX_LIST_ITEMS", "100"))

# Created once per execution environment and reused on warm invocations.
_dynamodb = boto3.resource("dynamodb")
_table = _dynamodb.Table(TABLE_NAME)


class BadRequest(Exception):
    """Raised for invalid input. Mapped to HTTP 400 by API Gateway."""


def _json_default(value):
    if isinstance(value, Decimal):
        return int(value) if value % 1 == 0 else float(value)
    raise TypeError(f"Object of type {type(value).__name__} is not JSON serializable")


def _to_dynamo(value):
    """Convert floats to Decimal, which is what DynamoDB expects."""
    return json.loads(json.dumps(value), parse_float=Decimal)


def _require(payload, *keys):
    missing = [k for k in keys if k not in payload]
    if missing:
        raise BadRequest(f"payload is missing: {', '.join(missing)}")


def op_create(payload):
    _require(payload, "Item")
    _table.put_item(Item=_to_dynamo(payload["Item"]))
    return {"status": "created", "id": payload["Item"].get("id")}


def op_read(payload):
    _require(payload, "Key")
    response = _table.get_item(Key=payload["Key"])
    return response.get("Item", {})


def op_update(payload):
    _require(payload, "Key", "UpdateExpression", "ExpressionAttributeValues")
    kwargs = {
        "Key": payload["Key"],
        "UpdateExpression": payload["UpdateExpression"],
        "ExpressionAttributeValues": _to_dynamo(payload["ExpressionAttributeValues"]),
        "ReturnValues": "ALL_NEW",
    }
    if "ExpressionAttributeNames" in payload:
        kwargs["ExpressionAttributeNames"] = payload["ExpressionAttributeNames"]
    return _table.update_item(**kwargs).get("Attributes", {})


def op_delete(payload):
    _require(payload, "Key")
    _table.delete_item(Key=payload["Key"])
    return {"status": "deleted"}


def op_list(payload):
    # A capped scan. Fine for a demo table; use Query with a key design for real workloads.
    limit = min(int(payload.get("Limit", MAX_LIST_ITEMS)), MAX_LIST_ITEMS)
    response = _table.scan(Limit=limit)
    return {"Items": response.get("Items", []), "Count": response.get("Count", 0)}


def op_echo(payload):
    return payload


def op_ping(_payload):
    return "pong"


OPERATIONS = {
    "create": op_create,
    "read": op_read,
    "update": op_update,
    "delete": op_delete,
    "list": op_list,
    "echo": op_echo,
    "ping": op_ping,
}


def lambda_handler(event, context):
    operation = event.get("operation")
    table_name = event.get("tableName", TABLE_NAME)
    payload = event.get("payload") or {}

    LOG.info(json.dumps({"operation": operation, "requestId": getattr(context, "aws_request_id", None)}))

    try:
        if operation not in OPERATIONS:
            raise BadRequest(f"unknown operation '{operation}'. Use one of: {', '.join(OPERATIONS)}")
        if table_name != TABLE_NAME:
            raise BadRequest("tableName is not allowed")
        if not isinstance(payload, dict):
            raise BadRequest("payload must be a JSON object")

        result = OPERATIONS[operation](payload)
        # Round-trip through json so Decimals become plain numbers for API Gateway.
        return json.loads(json.dumps(result, default=_json_default))

    except BadRequest as err:
        # The "[BadRequest]" prefix is matched by the API Gateway integration response -> 400.
        raise Exception(f"[BadRequest] {err}") from None
    except ClientError as err:
        LOG.error("DynamoDB error: %s", err)
        raise Exception("[InternalError] DynamoDB request failed") from None
