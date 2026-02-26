#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# HARD-CODED VALUES (REPLACE THESE)
###############################################################################
DT_ENV_URL="https://ENVIRONMENTID.live.dynatrace.com"     # or https://<managed-domain>/e/<env-id>
DT_ADMIN_TOKEN="dt0c01.REPLACE_ME"                       # MUST include apiTokens.write
CLUSTER_NAME="my-eks-cluster"
EXPIRY="now+365d"                                        # optional: now+30d, now+180d, now+1y

###############################################################################
# Logging helpers
###############################################################################
log() { printf "\n[%s] %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }
warn() { printf "\n[%s] WARN: %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }
die() { printf "\n[%s] ERROR: %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

###############################################################################
# Install curl/jq if missing
###############################################################################
install_pkgs() {
  local pkgs=("$@")

  if have dnf; then
    log "Installing via dnf: ${pkgs[*]}"
    sudo -n true 2>/dev/null || warn "sudo may prompt; run as root if this fails"
    sudo dnf -y install "${pkgs[@]}" || dnf -y install "${pkgs[@]}"
    return 0
  fi

  if have yum; then
    log "Installing via yum: ${pkgs[*]}"
    sudo -n true 2>/dev/null || warn "sudo may prompt; run as root if this fails"
    sudo yum -y install "${pkgs[@]}" || yum -y install "${pkgs[@]}"
    return 0
  fi

  if have apt-get; then
    log "Installing via apt-get: ${pkgs[*]}"
    sudo -n true 2>/dev/null || warn "sudo may prompt; run as root if this fails"
    sudo apt-get update -y || apt-get update -y
    sudo apt-get install -y "${pkgs[@]}" || apt-get install -y "${pkgs[@]}"
    return 0
  fi

  if have apk; then
    log "Installing via apk: ${pkgs[*]}"
    apk add --no-cache "${pkgs[@]}"
    return 0
  fi

  if have zypper; then
    log "Installing via zypper: ${pkgs[*]}"
    sudo -n true 2>/dev/null || warn "sudo may prompt; run as root if this fails"
    sudo zypper --non-interactive install "${pkgs[@]}" || zypper --non-interactive install "${pkgs[@]}"
    return 0
  fi

  return 1
}

ensure_tools() {
  local missing=()

  have curl || missing+=("curl")
  have jq   || missing+=("jq")

  if ((${#missing[@]} == 0)); then
    log "curl and jq already available."
    return 0
  fi

  warn "Missing tools: ${missing[*]}"
  warn "Attempting to install missing tools via available package manager..."

  if ! install_pkgs "${missing[@]}"; then
    warn "No supported package manager found OR install failed."
    warn "Proceeding with fallbacks (python3 JSON parsing if available)."
  fi
}

###############################################################################
# Minimal JSON creation and parsing
###############################################################################
json_escape() {
  # Escape string for JSON value (best-effort; good enough for simple inputs)
  python3 - <<'PY' "$1" 2>/dev/null || {
import json,sys
print(json.dumps(sys.argv[1]))
}
PY
}

build_payload_nojq() {
  # Args: name expiry scopes...
  local name="$1"; shift
  local expiry="$1"; shift
  local scopes=("$@")

  # Build JSON array of scopes
  local scopes_json="["
  local first=1
  for s in "${scopes[@]}"; do
    if [[ $first -eq 1 ]]; then first=0; else scopes_json+=", "; fi
    # quote scope safely using python if possible
    if have python3; then
      scopes_json+="$(python3 - <<'PY' "$s" 2>/dev/null || true
import json,sys
print(json.dumps(sys.argv[1]))
PY
)"
    else
      scopes_json+="\"$s\""
    fi
  done
  scopes_json+="]"

  # Quote name/expiry safely
  local qname qexp
  if have python3; then
    qname="$(python3 - <<'PY' "$name" 2>/dev/null
import json,sys
print(json.dumps(sys.argv[1]))
PY
)"
    qexp="$(python3 - <<'PY' "$expiry" 2>/dev/null
import json,sys
print(json.dumps(sys.argv[1]))
PY
)"
  else
    qname="\"$name\""
    qexp="\"$expiry\""
  fi

  cat <<EOF
{
  "name": ${qname},
  "expirationDate": ${qexp},
  "scopes": ${scopes_json}
}
EOF
}

extract_token_from_json() {
  # Reads JSON from stdin, prints .token
  if have jq; then
    jq -r '.token'
    return 0
  fi

  if have python3; then
    python3 - <<'PY'
import sys, json
data = sys.stdin.read()
obj = json.loads(data)
print(obj.get("token",""))
PY
    return 0
  fi

  # Last-resort naive parsing (works if response contains: "token":"..."):
  sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

extract_error_from_json() {
  # Reads JSON from stdin, prints .error.message if present
  if have jq; then
    jq -r '.error.message? // empty'
    return 0
  fi

  if have python3; then
    python3 - <<'PY'
import sys, json
data = sys.stdin.read()
try:
  obj = json.loads(data)
  err = obj.get("error", {})
  msg = err.get("message", "")
  print(msg or "")
except Exception:
  print("")
PY
    return 0
  fi

  # naive: try to find "message":"..."
  sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1
}

###############################################################################
# Dynatrace API calls
###############################################################################
api_post() {
  local path="$1"
  local payload="$2"

  curl -sS -X POST "${DT_ENV_URL}${path}" \
    -H "Authorization: Api-Token ${DT_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${payload}"
}

create_token() {
  local name="$1"; shift
  local expiry="$1"; shift
  local scopes=("$@")

  local payload resp token err

  if have jq; then
    payload="$(jq -n \
      --arg name "$name" \
      --arg expirationDate "$expiry" \
      --argjson scopes "$(printf '%s\n' "${scopes[@]}" | jq -R . | jq -s .)" \
      '{name:$name, expirationDate:$expirationDate, scopes:$scopes}')"
  else
    payload="$(build_payload_nojq "$name" "$expiry" "${scopes[@]}")"
  fi

  resp="$(api_post "/api/v2/apiTokens" "${payload}")"

  # Detect API error message
  err="$(printf '%s' "$resp" | extract_error_from_json)"
  if [[ -n "$err" ]]; then
    warn "Dynatrace API returned error: $err"
    warn "Full response (for debugging):"
    printf '%s\n' "$resp" >&2
    exit 1
  fi

  token="$(printf '%s' "$resp" | extract_token_from_json)"
  [[ -n "$token" && "$token" != "null" ]] || die "Failed to extract token from response. Response: $resp"
  printf '%s' "$token"
}

###############################################################################
# MAIN
###############################################################################
log "Ensuring dependencies (curl/jq if possible)..."
ensure_tools

have curl || die "curl is required but not available (and install failed)."
if ! have jq; then
  warn "jq not available. Will use python3 or fallback parsing."
  have python3 || warn "python3 not found either; parsing will be best-effort."
fi

log "Creating Dynatrace Operator token..."
# Scopes based on Dynatrace Kubernetes Operator token permissions (quickstart path)
# Depending on your Dynatrace version/requirements, you may not need all of these.
OPERATOR_TOKEN_NAME="k8s-${CLUSTER_NAME}-dynatrace-operator"
OPERATOR_TOKEN="$(create_token "$OPERATOR_TOKEN_NAME" "$EXPIRY" \
  "InstallerDownload" \
  "DataExport" \
  "settings.read" \
  "settings.write" \
  "activeGateTokenManagement.create" \
  "entities.read" \
)"

log "Creating Data Ingest token..."
INGEST_TOKEN_NAME="k8s-${CLUSTER_NAME}-data-ingest"
DATA_INGEST_TOKEN="$(create_token "$INGEST_TOKEN_NAME" "$EXPIRY" \
  "metrics.ingest" \
  "logs.ingest" \
  "openTelemetryTrace.ingest" \
)"

echo
echo "==================== CREATED TOKENS ===================="
echo "Dynatrace Environment : ${DT_ENV_URL}"
echo "Cluster name          : ${CLUSTER_NAME}"
echo
echo "Operator token name   : ${OPERATOR_TOKEN_NAME}"
echo "OPERATOR_TOKEN        : ${OPERATOR_TOKEN}"
echo
echo "Ingest token name     : ${INGEST_TOKEN_NAME}"
echo "DATA_INGEST_TOKEN     : ${DATA_INGEST_TOKEN}"
echo "========================================================"
echo
echo "Next step (per Dynatrace quickstart): create the dynakube secret in your cluster:"
echo "kubectl -n dynatrace create secret generic dynakube \\"
echo "  --from-literal=\"apiToken=${OPERATOR_TOKEN}\" \\"
echo "  --from-literal=\"dataIngestToken=${DATA_INGEST_TOKEN}\""
echo
echo "If dynatrace namespace doesn't exist yet:"
echo "kubectl create namespace dynatrace"