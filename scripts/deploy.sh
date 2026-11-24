#!/usr/bin/env bash
# Packages the Lambda code, deploys the CloudFormation stack and prints the outputs.
#
#   ./scripts/deploy.sh                                   # defaults: us-west-2, 1024 MB, no custom domain
#   MEMORY=128 ./scripts/deploy.sh                        # deploy at a different memory size
#   DOMAIN=api.example.com ZONE_ID=Z123... ./scripts/deploy.sh   # with a custom domain
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
STACK="${STACK:-lambda-power-tuning-demo}"
MEMORY="${MEMORY:-1024}"
DOMAIN="${DOMAIN:-}"
ZONE_ID="${ZONE_ID:-}"
ENABLE_WAF="${ENABLE_WAF:-true}"
WAF_RATE_LIMIT="${WAF_RATE_LIMIT:-2000}"
SET_APIGW_LOG_ROLE="${SET_APIGW_LOG_ROLE:-true}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ARTIFACTS="${ARTIFACTS_BUCKET:-${STACK}-artifacts-${ACCOUNT_ID}-${REGION}}"

if ! aws s3api head-bucket --bucket "$ARTIFACTS" 2>/dev/null; then
  echo "Creating artifacts bucket $ARTIFACTS"
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$ARTIFACTS" --region "$REGION" >/dev/null
  else
    aws s3api create-bucket --bucket "$ARTIFACTS" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  fi
  aws s3api put-public-access-block --bucket "$ARTIFACTS" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

mkdir -p "$ROOT/.build"
aws cloudformation package \
  --region "$REGION" \
  --template-file "$ROOT/infrastructure/template.yaml" \
  --s3-bucket "$ARTIFACTS" \
  --output-template-file "$ROOT/.build/packaged.yaml"

aws cloudformation deploy \
  --region "$REGION" \
  --stack-name "$STACK" \
  --template-file "$ROOT/.build/packaged.yaml" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    ProjectName="$STACK" \
    LambdaMemorySize="$MEMORY" \
    EnableWaf="$ENABLE_WAF" \
    WafRateLimit="$WAF_RATE_LIMIT" \
    ConfigureApiGatewayLoggingRole="$SET_APIGW_LOG_ROLE" \
    CustomDomainName="$DOMAIN" \
    HostedZoneId="$ZONE_ID"

aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" --output table

KEY_ID="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='ApiKeyId'].OutputValue" --output text)"
echo
echo "Get the API key value for Postman (keep it out of git):"
echo "  aws apigateway get-api-key --region $REGION --api-key $KEY_ID --include-value --query value --output text"
