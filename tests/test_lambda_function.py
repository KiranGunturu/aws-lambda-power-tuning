"""Unit tests for the Lambda handler, using moto to mock DynamoDB.

Run:  pip install -r tests/requirements.txt && python -m pytest -q tests
"""
import importlib
import os
import sys

import boto3
import pytest
from moto import mock_aws

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
TABLE = "lambda-apigateway"


@pytest.fixture
def handler(monkeypatch):
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-west-2")
    monkeypatch.setenv("TABLE_NAME", TABLE)
    with mock_aws():
        boto3.client("dynamodb").create_table(
            TableName=TABLE,
            AttributeDefinitions=[{"AttributeName": "id", "AttributeType": "S"}],
            KeySchema=[{"AttributeName": "id", "KeyType": "HASH"}],
            BillingMode="PAY_PER_REQUEST",
        )
        import lambda_function
        importlib.reload(lambda_function)
        yield lambda_function.lambda_handler


def call(handler, operation, payload=None, **extra):
    return handler({"operation": operation, "payload": payload or {}, **extra}, None)


def test_crud_roundtrip(handler):
    call(handler, "create", {"Item": {"id": "1", "price": 9.5, "qty": 2}})
    assert call(handler, "read", {"Key": {"id": "1"}}) == {"id": "1", "price": 9.5, "qty": 2}

    updated = call(handler, "update", {
        "Key": {"id": "1"},
        "UpdateExpression": "SET qty = :q",
        "ExpressionAttributeValues": {":q": 5},
    })
    assert updated["qty"] == 5

    assert call(handler, "list")["Count"] == 1
    call(handler, "delete", {"Key": {"id": "1"}})
    assert call(handler, "read", {"Key": {"id": "1"}}) == {}


def test_ping_and_echo(handler):
    assert call(handler, "ping") == "pong"
    assert call(handler, "echo", {"a": 1}) == {"a": 1}


def test_unknown_operation_is_bad_request(handler):
    with pytest.raises(Exception, match=r"\[BadRequest\]"):
        call(handler, "drop")


def test_other_table_is_rejected(handler):
    with pytest.raises(Exception, match=r"\[BadRequest\] tableName"):
        call(handler, "list", tableName="someone-elses-table")


def test_missing_key_is_bad_request(handler):
    with pytest.raises(Exception, match=r"\[BadRequest\] payload is missing: Key"):
        call(handler, "read", {})
