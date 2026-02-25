#!/usr/bin/env bash
set -euo pipefail
set +x

source "$(dirname "$0")/common.sh"
need_bin curl
need_bin jq

# ---- Inputs (set by Harness) ----
require_env PE_HOST_URL
require_env PE_CLIENT_ID
require_env PE_CLIENT_SECRET
require_env EMAIL_ID

# Token request fields (recommended for multi-team reuse)
require_env BUSINESS_UNIT
require_env LOCATION
require_env ENVIRONMENT
require_env INFRA_TYPE
require_env APPLICATION_NAME
require_env ACCESS_CATEGORY
require_env COMMENT
require_env OWNER_ID
require_env START_DATE
require_env END_DATE
require_env AUTO_RENEW

# JSON array string, e.g. '["InstallerDownload","settings.read",...]'
require_env ACCESS_DETAILS_JSON

PE_LOGIN_URL="${PE_HOST_URL%/}/api/v1/login"
PE_TOKENAPI_URL="${PE_HOST_URL%/}/api/v1/tokenapi/create"

# ---- Step A: login to PE to get BearerToken ----
login_resp="$(curl -sS -X GET "${PE_LOGIN_URL}" \
  -H "accept: application/json" \
  -H "client_id: ${PE_CLIENT_ID}" \
  -H "client_secret: ${PE_CLIENT_SECRET}")"

BEARER_TOKEN="$(echo "${login_resp}" | jq -r '.BearerToken // .bearerToken // .token // empty')"
if [[ -z "${BEARER_TOKEN}" ]]; then
  echo "ERROR: PE login did not return BearerToken. Response (truncated):" >&2
  echo "${login_resp}" | head -c 800 >&2 || true
  exit 1
fi

# ---- Step B: build JSON payload safely with jq (no quoting issues) ----
payload="$(jq -nc \
  --arg businessUnit "$BUSINESS_UNIT" \
  --arg location "$LOCATION" \
  --arg environment "$ENVIRONMENT" \
  --arg infrastructureType "$INFRA_TYPE" \
  --arg applicationName "$APPLICATION_NAME" \
  --arg accessCategory "$ACCESS_CATEGORY" \
  --arg comment "$COMMENT" \
  --arg ownerID "$OWNER_ID" \
  --arg startDate "$START_DATE" \
  --arg endDate "$END_DATE" \
  --arg autoRenew "$AUTO_RENEW" \
  --arg test "${TEST_FIELD:-}" \
  --argjson accessDetails "$ACCESS_DETAILS_JSON" \
  '{
    businessUnit:$businessUnit,
    location:$location,
    environment:$environment,
    infrastructureType:$infrastructureType,
    accessDetails:$accessDetails,
    startDate:$startDate,
    endDate:$endDate,
    applicationName:$applicationName,
    accessCategory:$accessCategory,
    comment:$comment,
    ownerID:$ownerID,
    autoRenew:$autoRenew,
    test:$test
  }'
)"

# ---- Step C: call tokenapi/create ----
create_resp="$(curl -sS -X POST "${PE_TOKENAPI_URL}" \
  -H "accept: application/json" \
  -H "content-type: application/json" \
  -H "emailId: ${EMAIL_ID}" \
  -H "Authorization: Bearer ${BEARER_TOKEN}" \
  -d "${payload}")"

# ---- Step D: extract Vault details from PE response ----
# PE response contract can vary; we try common shapes. Update/extend these jq paths once confirmed.
ROLE_ID="$(jq_pick "$create_resp" \
  '.vault.role_id' '.vault.roleId' '.role_id' '.roleId' '.data.vault.role_id' '.data.role_id' '.data.roleId' )"

SECRET_ID="$(jq_pick "$create_resp" \
  '.vault.secret_id' '.vault.secretId' '.secret_id' '.secretId' '.data.vault.secret_id' '.data.secret_id' '.data.secretId' )"

VAULT_ADDR="$(jq_pick "$create_resp" \
  '.vault.addr' '.vault.vault_addr' '.vault.vaultAddr' '.vault_addr' '.vaultAddr' '.data.vault.addr' '.data.vault_addr' '.data.vaultAddr' )"

VAULT_NAMESPACE="$(jq_pick "$create_resp" \
  '.vault.namespace' '.vault.vault_namespace' '.vault.vaultNamespace' '.vault_namespace' '.vaultNamespace' '.data.vault.namespace' '.data.vault_namespace' '.data.vaultNamespace' )"

DT_ACCESS_SECRET_PATH="$(jq_pick "$create_resp" \
  '.vault.secret_path' '.vault.secretPath' '.secret_path' '.secretPath' '.vault_path' '.vaultPath' '.data.vault.secret_path' '.data.secret_path' '.data.secretPath' )"

if [[ -z "$VAULT_ADDR" ]]; then
  echo "ERROR: Could not extract VAULT_ADDR from PE /tokenapi/create response." >&2
  echo "${create_resp}" | head -c 1200 >&2 || true
  exit 1
fi
if [[ -z "$DT_ACCESS_SECRET_PATH" ]]; then
  echo "ERROR: Could not extract DT_ACCESS_SECRET_PATH from PE /tokenapi/create response." >&2
  echo "${create_resp}" | head -c 1200 >&2 || true
  exit 1
fi

# ---- Step E: rerun-safe handling for ROLE_ID / SECRET_ID ----
# PE returns these only on first run. If missing, use overrides (stored in Harness secrets).
if [[ -z "$ROLE_ID" || -z "$SECRET_ID" ]]; then
  if [[ -n "${VAULT_ROLE_ID_OVERRIDE:-}" && -n "${VAULT_SECRET_ID_OVERRIDE:-}" ]]; then
    ROLE_ID="${VAULT_ROLE_ID_OVERRIDE}"
    SECRET_ID="${VAULT_SECRET_ID_OVERRIDE}"
  else
    echo "ERROR: PE did not return role_id/secret_id (likely rerun) AND overrides are not provided." >&2
    echo "Set VAULT_ROLE_ID_OVERRIDE and VAULT_SECRET_ID_OVERRIDE from Harness secrets for reruns." >&2
    exit 1
  fi
fi

# ---- Harness Output Variables (declare them) ----
ROLE_ID="${ROLE_ID}"
SECRET_ID="${SECRET_ID}"
VAULT_ADDR="${VAULT_ADDR}"
VAULT_NAMESPACE="${VAULT_NAMESPACE}"
DT_ACCESS_SECRET_PATH="${DT_ACCESS_SECRET_PATH}"

# Safe logging
echo "Stage1: Vault addr=${VAULT_ADDR} namespace=${VAULT_NAMESPACE:-<none>} secret_path=${DT_ACCESS_SECRET_PATH}"
echo "Stage1: role_id=$(mask "$ROLE_ID") secret_id=$(mask "$SECRET_ID")"
