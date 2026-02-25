#!/usr/bin/env bash
set -euo pipefail
set +x

source "$(dirname "$0")/common.sh"
need_bin curl
need_bin jq

require_env VAULT_ADDR
require_env ROLE_ID
require_env SECRET_ID
require_env DT_ACCESS_SECRET_PATH

DT_ACCESS_TOKEN_FIELD="${DT_ACCESS_TOKEN_FIELD:-dynatrace_access_token}"

# AppRole login
login_url="${VAULT_ADDR%/}/v1/auth/approle/login"
login_payload="$(jq -nc --arg r "$ROLE_ID" --arg s "$SECRET_ID" '{role_id:$r,secret_id:$s}')"

vault_headers=()
if [[ -n "${VAULT_NAMESPACE:-}" ]]; then
  vault_headers+=(-H "x-vault-namespace: ${VAULT_NAMESPACE}")
fi

login_resp="$(curl -sS -X POST "$login_url" \
  "${vault_headers[@]}" \
  -H "content-type: application/json" \
  -d "$login_payload")"

VAULT_TOKEN="$(echo "$login_resp" | jq -r '.auth.client_token // empty')"
if [[ -z "$VAULT_TOKEN" ]]; then
  echo "ERROR: Vault login failed. Response (truncated):" >&2
  echo "$login_resp" | head -c 1000 >&2 || true
  exit 1
fi

# Read secret (KVv2 preferred)
read_url="${VAULT_ADDR%/}/v1/${DT_ACCESS_SECRET_PATH}"
read_resp="$(curl -sS -X GET "$read_url" \
  "${vault_headers[@]}" \
  -H "accept: application/json" \
  -H "x-vault-token: ${VAULT_TOKEN}")"

DT_ACCESS_TOKEN="$(echo "$read_resp" | jq -r --arg f "$DT_ACCESS_TOKEN_FIELD" '.data.data[$f] // .data[$f] // empty')"
if [[ -z "$DT_ACCESS_TOKEN" ]]; then
  echo "ERROR: Could not read field '$DT_ACCESS_TOKEN_FIELD' from Vault secret at path ${DT_ACCESS_SECRET_PATH}." >&2
  echo "$read_resp" | head -c 1200 >&2 || true
  exit 1
fi

# Harness output
DT_ACCESS_TOKEN="${DT_ACCESS_TOKEN}"

echo "Stage2: Retrieved DT access token length=${#DT_ACCESS_TOKEN}"
