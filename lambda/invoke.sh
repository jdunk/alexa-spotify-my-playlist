#!/bin/bash
set -euo pipefail

# Load environment variables from .env
set -a
. .env
set +a

PLAYLIST_NAME="${1:-}"

if [[ -z "$PLAYLIST_NAME" ]]; then
  echo "❌ Usage: $0 \"Playlist Name\""
  exit 1
fi

PAYLOAD=$(jq -n \
  --arg name "$PLAYLIST_NAME" \
  '{
    request: {
      type: "IntentRequest",
      intent: {
        name: "PlayPlaylistIntent",
        slots: {
          playlistName: { value: $name }
        }
      }
    }
  }'
)

aws lambda invoke \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --cli-binary-format raw-in-base64-out \
  --payload "$PAYLOAD" \
  response.json

echo "✅ Invocation complete. Response saved to response.json"
jq . response.json