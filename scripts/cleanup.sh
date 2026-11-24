#!/usr/bin/env bash
# Deletes the demo stack. The results bucket is retained on purpose (DeletionPolicy: Retain);
# pass --purge-results to empty and delete it as well.
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
STACK="${STACK:-lambda-power-tuning-demo}"

BUCKET="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='ResultsBucketName'].OutputValue" --output text 2>/dev/null || true)"

aws cloudformation delete-stack --region "$REGION" --stack-name "$STACK"
aws cloudformation wait stack-delete-complete --region "$REGION" --stack-name "$STACK"
echo "Stack $STACK deleted."

if [ "${1:-}" = "--purge-results" ] && [ -n "$BUCKET" ] && [ "$BUCKET" != "None" ]; then
  echo "Emptying and deleting $BUCKET (all versions)..."
  python3 - "$BUCKET" "$REGION" <<'PY'
import sys, boto3
bucket = boto3.resource("s3", region_name=sys.argv[2]).Bucket(sys.argv[1])
bucket.object_versions.delete()
bucket.delete()
PY
fi

echo "If you deployed Power Tuning, delete it too:"
echo "  aws cloudformation delete-stack --region $REGION --stack-name serverlessrepo-aws-lambda-power-tuning"
