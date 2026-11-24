#!/usr/bin/env bash
# Smoke test: one good request, plus the security checks that should be rejected.
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
STACK="${STACK:-lambda-power-tuning-demo}"

out() { aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text; }

URL="${URL:-$(out InvokeUrl)}"
API_KEY="${API_KEY:-$(aws apigateway get-api-key --region "$REGION" --api-key "$(out ApiKeyId)" --include-value --query value --output text)}"

call() { # $1 = expected status, $2 = body, $3 = "nokey" to omit the key
  local headers=(-H "Content-Type: application/json")
  [ "${3:-}" != "nokey" ] && headers+=(-H "x-api-key: $API_KEY")
  local status
  status="$(curl -s -o /tmp/resp.json -w '%{http_code}' -X POST "${headers[@]}" -d "$2" "$URL")"
  if [ "$status" = "$1" ]; then echo "PASS  $status  $2"; else echo "FAIL  got $status, expected $1  $2"; cat /tmp/resp.json; echo; fi
}

call 200 '{"operation":"ping","payload":{}}'
call 200 '{"operation":"list","tableName":"lambda-apigateway","payload":{}}'
call 403 '{"operation":"list","payload":{}}' nokey
call 400 '{"operation":"dropTable","payload":{}}'
call 400 '{"operation":"list","tableName":"some-other-table","payload":{}}'
