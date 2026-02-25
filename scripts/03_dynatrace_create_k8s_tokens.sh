#!/usr/bin/env bash
set -euo pipefail
set +x

source "$(dirname "$0")/common.sh"
need_bin curl
need_bin jq

require_env DT_ENV_URL
require_env DT_ACCESS_TOKEN
require_env CLUSTER_NAME

TOKEN_NAME_PREFIX="${TOKEN_NAME_PREFIX:-harness-k8s}"
ts="$(date -u +"%Y%m%dT%H%M%SZ")"

# Default scopes (adjust per your org / Dynatrace docs)
OPERATOR_SCOPES_CSV="${OPERATOR_SCOPES_CSV:-InstallerDownload,settings.read,settings.write,activeGateTokenManagement.create,entities.read,DataExport}"
INGEST_SCOPES_CSV="${INGEST_SCOPES_CSV:-metrics.ingest,logs.ingest,openTelemetryTrace.ingest}"

csv_to_json_array() {
  local csv="$1"
  jq -nc --arg csv "$csv" '$csv | split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length>0))'
}

create_token() {
  local name="$1"
  local scopes_json="$2"
  local url="${DT_ENV_URL%/}/api/v2/apiTokens"
  local payload
  payload="$(jq -nc --arg n "$name" --argjson s "$scopes_json" '{name:$n,scopes:$s}')"
  local resp
  resp="$(curl -sS -X POST "$url" \
    -H "content-type: application/json" \
    -H "Authorization: Api-Token ${DT_ACCESS_TOKEN}" \
    -d "$payload")"
  echo "$resp" | jq -r '.token // empty'
}

op_scopes="$(csv_to_json_array "$OPERATOR_SCOPES_CSV")"
ing_scopes="$(csv_to_json_array "$INGEST_SCOPES_CSV")"

DT_OPERATOR_TOKEN="$(create_token "${TOKEN_NAME_PREFIX}-operator-${CLUSTER_NAME}-${ts}" "$op_scopes")"
DT_DATA_INGEST_TOKEN="$(create_token "${TOKEN_NAME_PREFIX}-dataingest-${CLUSTER_NAME}-${ts}" "$ing_scopes")"

if [[ -z "$DT_OPERATOR_TOKEN" || -z "$DT_DATA_INGEST_TOKEN" ]]; then
  echo "ERROR: Failed to create Dynatrace tokens. Check DT_ENV_URL and DT_ACCESS_TOKEN scopes." >&2
  exit 1
fi

# Harness outputs
DT_OPERATOR_TOKEN="${DT_OPERATOR_TOKEN}"
DT_DATA_INGEST_TOKEN="${DT_DATA_INGEST_TOKEN}"

echo "Stage3: Created DT operator token len=${#DT_OPERATOR_TOKEN}, data ingest token len=${#DT_DATA_INGEST_TOKEN}"
