#!/usr/bin/env bash
#
# setup-devops-center-hub.sh
#
# Automates the CLI-automatable parts of plan/00-prereqs.md for a DevOps Center
# **Hub** org: assigns the three DevOps Center permission sets to the org's
# running user and verifies the result.
#
# Reusable across environments — pass any authenticated target-org alias or
# username. What it does NOT do (UI-only, by design): accept the DX Tools T&C
# on first open of the DevOps Center app.
#
# Usage:
#   scripts/setup-devops-center-hub.sh --target-org afd360-prod
#   scripts/setup-devops-center-hub.sh -o admin@some.other.org
#
# Requires: sf CLI (authenticated to the target org) and jq.
#
set -euo pipefail

# --- DevOps Center permission sets (API names, NOT UI labels) -----------------
#   DevOpsCenterManager        = "Lifecycle Center Admin"      (was "DevOps Center Admin" before Winter '27)
#   DevOpsCenter               = "Lifecycle Center User"       (was "DevOps Center User")
#   DevOpsCenterReleaseManager = "Lifecycle Center Deployment Manager" (was "DevOps Center Deployment Manager")
PERMSETS=(DevOpsCenterManager DevOpsCenter DevOpsCenterReleaseManager)

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }

TARGET_ORG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--target-org) TARGET_ORG="${2:-}"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$TARGET_ORG" ]]; then
  echo "ERROR: --target-org <alias|username> is required" >&2
  usage; exit 2
fi

command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 3; }

echo "==> Target org: $TARGET_ORG"

echo "==> Verifying connectivity..."
USERNAME=$(sf org display --target-org "$TARGET_ORG" --json | jq -r '.result.username')
echo "    connected as: $USERNAME"

echo "==> Confirming DevOps Center permission sets exist (is DevOps Center enabled?)..."
FOUND=$(sf data query --target-org "$TARGET_ORG" --json \
  --query "SELECT Name FROM PermissionSet WHERE Name IN ('DevOpsCenterManager','DevOpsCenter','DevOpsCenterReleaseManager')" \
  | jq -r '.result.records | length')
if [[ "$FOUND" -lt 3 ]]; then
  echo "ERROR: found only $FOUND/3 DevOps Center permission sets in this org." >&2
  echo "       DevOps Center may not be enabled here. Enable it and re-run." >&2
  exit 1
fi

echo "==> Assigning permission sets: ${PERMSETS[*]}"
# Idempotent: re-running reports already-assigned sets as a warning, not a failure.
sf org assign permset --name "${PERMSETS[@]}" --target-org "$TARGET_ORG" || true

echo "==> Verifying assignments for $USERNAME ..."
# Filter the assignee client-side in jq: SOQL relationship filters on
# Assignee.Username proved flaky against freshly-created assignments.
ASSIGNED=$(sf data query --target-org "$TARGET_ORG" --json \
  --query "SELECT Assignee.Username, PermissionSet.Name FROM PermissionSetAssignment WHERE PermissionSet.Name IN ('DevOpsCenterManager','DevOpsCenter','DevOpsCenterReleaseManager')" \
  | jq -r --arg u "$USERNAME" '.result.records[] | select(.Assignee.Username == $u) | .PermissionSet.Name' | sort -u)

COUNT=$(printf '%s\n' "$ASSIGNED" | grep -c . || true)
printf '%s\n' "$ASSIGNED" | sed 's/^/    ✓ /'

if [[ "$COUNT" -lt 3 ]]; then
  echo "ERROR: expected 3 assignments, verified $COUNT. Check the org manually." >&2
  exit 1
fi

echo "==> Done: DevOps Center Hub permission sets assigned to $USERNAME on $TARGET_ORG."
echo "    Remaining manual step: open App Launcher -> DevOps Center once and accept the DX Tools T&C."
