#!/usr/bin/env bash
# Changes the function's memory between load test runs, then waits for the update to finish.
#   ./scripts/set-memory.sh 128
#   ./scripts/set-memory.sh 1024
# For a permanent change, redeploy with MEMORY=<value> ./scripts/deploy.sh so the stack doesn't drift.
set -euo pipefail

MEMORY="${1:?usage: set-memory.sh <memory-mb>}"
REGION="${AWS_REGION:-us-west-2}"
FUNCTION="${FUNCTION:-LambdaFunctionOverHttps}"

aws lambda update-function-configuration --region "$REGION" --function-name "$FUNCTION" \
  --memory-size "$MEMORY" --query "[FunctionName,MemorySize]" --output text
aws lambda wait function-updated --region "$REGION" --function-name "$FUNCTION"
echo "Done. Wait a minute before the next load test so both runs start from the same cold state."
