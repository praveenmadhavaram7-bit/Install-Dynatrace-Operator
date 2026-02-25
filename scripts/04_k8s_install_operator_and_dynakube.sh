#!/usr/bin/env bash
set -euo pipefail
set +x

source "$(dirname "$0")/common.sh"
need_bin kubectl
need_bin helm
need_bin envsubst

require_env DT_OPERATOR_TOKEN
require_env DT_DATA_INGEST_TOKEN
require_env CLUSTER_NAME
require_env NETWORK_ZONE
require_env DT_ENV_URL

DT_NAMESPACE="${DT_NAMESPACE:-dynatrace}"
DYNATRACE_OPERATOR_VERSION="${DYNATRACE_OPERATOR_VERSION:-1.7.3}"

# Dynatrace API URL usually is <env>/api
DT_API_URL="${DT_API_URL:-${DT_ENV_URL%/}/api}"

# DynaKube token secret name; default = cluster name
SECRET_NAME="${SECRET_NAME:-$CLUSTER_NAME}"
HOST_GROUP="${HOST_GROUP:-default-hostgroup}"

# ActiveGate sizing defaults
AG_REQ_CPU="${AG_REQ_CPU:-200m}"
AG_REQ_MEM="${AG_REQ_MEM:-512Mi}"
AG_LIM_CPU="${AG_LIM_CPU:-500m}"
AG_LIM_MEM="${AG_LIM_MEM:-1Gi}"

# 1) Namespace
kubectl get ns "$DT_NAMESPACE" >/dev/null 2>&1 || kubectl create ns "$DT_NAMESPACE"

# 2) Install operator from OCI
helm upgrade --install dynatrace-operator \
  oci://public.ecr.aws/dynatrace/dynatrace-operator \
  --namespace "$DT_NAMESPACE" \
  --create-namespace \
  --atomic \
  --wait \
  --timeout 10m \
  --version "$DYNATRACE_OPERATOR_VERSION"

# 3) Create token secret (avoid printing token values)
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
printf "%s" "$DT_OPERATOR_TOKEN" > "$tmpdir/apiToken"
printf "%s" "$DT_DATA_INGEST_TOKEN" > "$tmpdir/dataIngestToken"
chmod 600 "$tmpdir/apiToken" "$tmpdir/dataIngestToken"

kubectl -n "$DT_NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-file=apiToken="$tmpdir/apiToken" \
  --from-file=dataIngestToken="$tmpdir/dataIngestToken" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# 4) Apply DynaKube
export DT_NAMESPACE CLUSTER_NAME DT_API_URL NETWORK_ZONE HOST_GROUP SECRET_NAME AG_REQ_CPU AG_REQ_MEM AG_LIM_CPU AG_LIM_MEM
envsubst < "$(dirname "$0")/../templates/dynakube.yaml.tpl" | kubectl apply -f -

echo "Stage4: dynatrace namespace pods:"
kubectl -n "$DT_NAMESPACE" get pods -o wide || true

echo "Stage4: dynakube resources:"
kubectl -n "$DT_NAMESPACE" get dynakube -o wide || true
