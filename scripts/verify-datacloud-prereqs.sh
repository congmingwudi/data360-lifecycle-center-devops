#!/usr/bin/env bash
#
# verify-datacloud-prereqs.sh
#
# Verifies the Data Cloud prerequisites from plan/00-prereqs.md (§4 and §5) for
# one or more environments: that Data Cloud is provisioned, and that the data
# space the pipeline will use exists and is ACTIVE.
#
# Read-only — makes no changes. Reusable across environments: pass each org.
#
# Usage:
#   scripts/verify-datacloud-prereqs.sh -o afd360-dcdev1 -o afd360-dcstaging1
#   scripts/verify-datacloud-prereqs.sh -o afd360-dcstaging1 --data-space default
#
# Requires: sf CLI (authenticated to each org) and jq.
#
set -euo pipefail

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }

ORGS=()
DATA_SPACE="default"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--target-org) ORGS+=("${2:-}"); shift 2 ;;
    -d|--data-space) DATA_SPACE="${2:-}"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ ${#ORGS[@]} -gt 0 ]] || { echo "ERROR: at least one --target-org is required" >&2; usage; exit 2; }
command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 3; }

FAIL=0
for org in "${ORGS[@]}"; do
  echo "==> $org (expecting data space '$DATA_SPACE')"

  # DataSpace is queryable only when Data Cloud is provisioned. INVALID_TYPE => not provisioned.
  RESULT=$(sf data query --target-org "$org" --json \
    --query "SELECT Name, DataSpaceApiName, Status FROM DataSpace WHERE DataSpaceApiName = '$DATA_SPACE'" 2>&1 || true)

  if ! echo "$RESULT" | jq -e '.status == 0' >/dev/null 2>&1; then
    MSG=$(echo "$RESULT" | jq -r '.name // .message' 2>/dev/null || echo "$RESULT")
    echo "    ✗ Data Cloud probe failed: $MSG (Data Cloud may not be provisioned here)"
    FAIL=1
    continue
  fi

  STATUS=$(echo "$RESULT" | jq -r '.result.records[0].Status // empty')
  if [[ -z "$STATUS" ]]; then
    echo "    ✗ Data Cloud provisioned, but data space '$DATA_SPACE' not found — pre-create it before promoting here."
    FAIL=1
  elif [[ "$STATUS" != "ACTIVE" ]]; then
    echo "    ✗ Data space '$DATA_SPACE' exists but status=$STATUS (expected ACTIVE)."
    FAIL=1
  else
    echo "    ✓ Data Cloud provisioned; data space '$DATA_SPACE' is ACTIVE."
  fi
done

if [[ "$FAIL" -ne 0 ]]; then
  echo "==> One or more prerequisites are not met (see ✗ above)." >&2
  exit 1
fi
echo "==> All Data Cloud prerequisites met."
