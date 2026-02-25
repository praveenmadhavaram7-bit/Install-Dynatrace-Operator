#!/usr/bin/env bash
set -euo pipefail
set +x

require_env() {
  local n="$1"
  if [[ -z "${!n:-}" ]]; then
    echo "ERROR: missing required env var: $n" >&2
    exit 1
  fi
}

need_bin() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing binary: $1" >&2; exit 1; }
}

mask() {
  local s="${1:-}"
  local show="${2:-4}"
  if [[ -z "$s" ]]; then echo ""; return; fi
  if (( ${#s} <= show )); then printf '%*s' "${#s}" '' | tr ' ' '*'; return; fi
  echo "${s:0:show}$(printf '%*s' "$(( ${#s}-show ))" '' | tr ' ' '*')"
}

# Try multiple jq filters and return first non-empty
jq_pick() {
  local json="$1"; shift
  for f in "$@"; do
    local v
    v="$(echo "$json" | jq -r "$f // empty" 2>/dev/null || true)"
    if [[ -n "$v" && "$v" != "null" ]]; then
      echo "$v"
      return 0
    fi
  done
  echo ""
  return 1
}
