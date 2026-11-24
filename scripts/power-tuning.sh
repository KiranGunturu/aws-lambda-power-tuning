#!/usr/bin/env bash
# Deploys AWS Lambda Power Tuning from the Serverless Application Repository (once),
# runs it against this project's function and prints the result.
#
#   ./scripts/power-tuning.sh deploy     # one time
#   ./scripts/power-tuning.sh run        # every time you want to tune
set -euo pipefail

REGION="${AWS_REGION:-us-west-2}"
STACK="${STACK:-lambda-power-tuning-demo}"
TUNER_STACK="serverlessrepo-aws-lambda-power-tuning"
APP_ID="arn:aws:serverlessrepo:us-east-1:451282441545:applications/aws-lambda-power-tuning"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "${1:-run}" in
  deploy)
    CS_ARN="$(aws serverlessrepo create-cloud-formation-change-set --region "$REGION" \
      --application-id "$APP_ID" --stack-name aws-lambda-power-tuning \
      --capabilities CAPABILITY_IAM CAPABILITY_RESOURCE_POLICY \
      --query ChangeSetId --output text)"
    aws cloudformation wait change-set-create-complete --region "$REGION" --change-set-name "$CS_ARN"
    aws cloudformation execute-change-set --region "$REGION" --change-set-name "$CS_ARN"
    aws cloudformation wait stack-create-complete --region "$REGION" --stack-name "$TUNER_STACK"
    echo "Power Tuning deployed."
    ;;
  run)
    SM_ARN="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$TUNER_STACK" \
      --query "Stacks[0].Outputs[?OutputKey=='StateMachineARN'].OutputValue" --output text)"
    FN_ARN="$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
      --query "Stacks[0].Outputs[?OutputKey=='FunctionArn'].OutputValue" --output text)"
    INPUT="$(sed "s#arn:aws:lambda:us-west-2:<ACCOUNT_ID>:function:LambdaFunctionOverHttps#$FN_ARN#" "$ROOT/power-tuning/input.json")"

    EXEC_ARN="$(aws stepfunctions start-execution --region "$REGION" --state-machine-arn "$SM_ARN" \
      --input "$INPUT" --query executionArn --output text)"
    echo "Started $EXEC_ARN"
    while true; do
      STATUS="$(aws stepfunctions describe-execution --region "$REGION" --execution-arn "$EXEC_ARN" --query status --output text)"
      [ "$STATUS" != "RUNNING" ] && break
      sleep 5
    done
    echo "Status: $STATUS"
    aws stepfunctions describe-execution --region "$REGION" --execution-arn "$EXEC_ARN" --query output --output text \
      | tee "$ROOT/power-tuning/last-output.json"
    echo
    echo "Open the 'visualization' URL above to see the chart."
    ;;
  *) echo "usage: power-tuning.sh deploy|run"; exit 1 ;;
esac
