#!/bin/bash
set -euo pipefail

# --- Load .env ---
set -a
. .env
set +a

# --- Required envs ---
: "${LAMBDA_FUNCTION_NAME:?Set LAMBDA_FUNCTION_NAME in .env}"
: "${LAMBDA_ROLE_ARN:?Set LAMBDA_ROLE_ARN in .env}"

# --- Paths / config ---
ZIP_PATH="deploy/${LAMBDA_FUNCTION_NAME}.zip"
LAMBDA_DIR="lambda"
RUNTIME_FILE="index.mjs"
ENV_JSON_PATH="deploy/env.json"

# --- AWS args ---
AWS_ARGS=()
[[ -n "${AWS_REGION:-}"  ]] && AWS_ARGS+=(--region "$AWS_REGION")
[[ -n "${AWS_PROFILE:-}" ]] && AWS_ARGS+=(--profile "$AWS_PROFILE")

# --- Precheck ---
cd "$(dirname "$0")/.."
[[ -f "${LAMBDA_DIR}/${RUNTIME_FILE}" ]] || { echo "❌ ${LAMBDA_DIR}/${RUNTIME_FILE} not found"; exit 1; }

# --- Zip ONLY the handler file ---
echo "📦 Zipping Lambda code (single file)…"
zip -j "$ZIP_PATH" "${LAMBDA_DIR}/${RUNTIME_FILE}" > /dev/null
echo "✅ Created: $ZIP_PATH"

# --- Create or update function ---
if aws "${AWS_ARGS[@]}" lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" > /dev/null 2>&1; then
  echo "🔁 Updating code…"
  aws "${AWS_ARGS[@]}" lambda update-function-code \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --zip-file "fileb://$ZIP_PATH" \
    --publish > /dev/null
else
  echo "🆕 Creating function…"
  aws "${AWS_ARGS[@]}" lambda create-function \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --runtime nodejs20.x \
    --role "$LAMBDA_ROLE_ARN" \
    --handler "index.handler" \
    --zip-file "fileb://$ZIP_PATH" \
    --timeout 10 \
    --memory-size 128 \
    --publish > /dev/null
fi

echo "⏳ Waiting for function to be ready…"
aws "${AWS_ARGS[@]}" lambda wait function-updated --function-name "$LAMBDA_FUNCTION_NAME"

# --- OPEN PERMISSION: allow any Alexa skill to invoke (no Skill ID token) ---
echo "🔓 Adding open Alexa permission (any skill)…"
if ! aws "${AWS_ARGS[@]}" lambda add-permission \
      --function-name "$LAMBDA_FUNCTION_NAME" \
      --action lambda:InvokeFunction \
      --principal alexa-appkit.amazon.com \
      --statement-id "AllowAllAlexa$(date +%s)" > /dev/null 2>&1; then
  echo "ℹ️  Permission may already exist; continuing."
fi

# --- Build environment JSON (include only set vars) ---
jq -n \
  --arg SPOTIFY_CLIENT_ID         "${SPOTIFY_CLIENT_ID:-}" \
  --arg SPOTIFY_CLIENT_SECRET     "${SPOTIFY_CLIENT_SECRET:-}" \
  --arg SPOTIFY_REFRESH_TOKEN     "${SPOTIFY_REFRESH_TOKEN:-}" \
  --arg DEFAULT_SPOTIFY_DEVICE_ID "${DEFAULT_SPOTIFY_DEVICE_ID:-}" \
  --arg ALEXA_DEVICE_ID_TO_SPOTIFY_DEVICE_ID_MAP "${ALEXA_DEVICE_ID_TO_SPOTIFY_DEVICE_ID_MAP}" \
  '{
    Variables:
      ( (if $SPOTIFY_CLIENT_ID         != "" then {SPOTIFY_CLIENT_ID:$SPOTIFY_CLIENT_ID} else {} end) +
        (if $SPOTIFY_CLIENT_SECRET     != "" then {SPOTIFY_CLIENT_SECRET:$SPOTIFY_CLIENT_SECRET} else {} end) +
        (if $SPOTIFY_REFRESH_TOKEN     != "" then {SPOTIFY_REFRESH_TOKEN:$SPOTIFY_REFRESH_TOKEN} else {} end) +
        (if $DEFAULT_SPOTIFY_DEVICE_ID != "" then {DEFAULT_SPOTIFY_DEVICE_ID:$DEFAULT_SPOTIFY_DEVICE_ID} else {} end) +
        (if $ALEXA_DEVICE_ID_TO_SPOTIFY_DEVICE_ID_MAP != "" then {ALEXA_DEVICE_ID_TO_SPOTIFY_DEVICE_ID_MAP: ($ALEXA_DEVICE_ID_TO_SPOTIFY_DEVICE_ID_MAP)} else {} end)
      )
  }' > "$ENV_JSON_PATH"

echo "🔧 Syncing environment variables…"
if ! aws "${AWS_ARGS[@]}" lambda update-function-configuration \
      --function-name "$LAMBDA_FUNCTION_NAME" \
      --environment "file://$ENV_JSON_PATH" > /dev/null; then
  echo "↻ Config update conflicted; waiting and retrying…"
  aws "${AWS_ARGS[@]}" lambda wait function-updated --function-name "$LAMBDA_FUNCTION_NAME"
  aws "${AWS_ARGS[@]}" lambda update-function-configuration \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --environment "file://$ENV_JSON_PATH" > /dev/null
fi

echo "✅ Deployment complete."