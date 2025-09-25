#!/bin/bash
set -euo pipefail

# Load environment variables
set -a
. .env
set +a

if [[ -z "${LAMBDA_FUNCTION_NAME:-}" ]]; then
  echo "❌ LAMBDA_FUNCTION_NAME is not set in .env"
  exit 1
fi

aws lambda invoke \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --cli-binary-format raw-in-base64-out \
  --payload '{}' /tmp/resp.json

echo "📡 Tailing logs for Lambda function: $LAMBDA_FUNCTION_NAME"
aws logs tail "/aws/lambda/$LAMBDA_FUNCTION_NAME" --follow --format short