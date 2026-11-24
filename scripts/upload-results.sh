#!/usr/bin/env bash
# Uploads load test and power tuning results to the encrypted results bucket created by the stack.
#
#   ./scripts/upload-results.sh                         # uploads load-testing/results and power-tuning/results.json
#   ./scripts/upload-results.sh ~/Downloads/run.json    # also uploads an exported Postman run
#
# Objects land under:  s3://<bucket>/runs/<YYYY-MM-DD>/...
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
STACK="${STACK:-lambda-power-tuning-demo}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DAY="$(date +%Y-%m-%d)"

BUCKET="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='ResultsBucketName'].OutputValue" --output text)"
PREFIX="s3://$BUCKET/runs/$DAY"

aws s3 cp "$ROOT/load-testing/results/" "$PREFIX/load-testing/" --recursive --region "$REGION" \
  --exclude "*" --include "*.json" --include "*.csv" --include "*.png"
aws s3 cp "$ROOT/power-tuning/results.json" "$PREFIX/power-tuning/results.json" --region "$REGION"

for extra in "$@"; do
  aws s3 cp "$extra" "$PREFIX/postman-exports/$(basename "$extra")" --region "$REGION"
done

echo
aws s3 ls "$PREFIX/" --recursive --region "$REGION"
