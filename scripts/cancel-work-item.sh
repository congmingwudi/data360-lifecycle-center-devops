#!/usr/bin/env bash
#
# cancel-work-item.sh
#
# Cancels a DevOps Center work item by setting its Status to NEVERED (the enum
# behind the "Never Mind" action). Use this to abandon a work item that can't be
# progressed — e.g. one left with a failed/stalled commit — so you can start a
# fresh work item. This is the *supported* abandon path; the DevOps Center UI
# offers no delete, and deleting the WorkItem row would orphan its Git branch and
# related control-plane records.
#
# Runs against the DevOps Center **Hub** org (where work items live). Idempotent:
# a work item already NEVERED is reported and left as-is. Self-verifying: exits
# non-zero unless the status ends up NEVERED.
#
# Note: NEVERED-ing a work item also removes its auto-created Git branch from the
# remote (observed 2026-09-28: WI-000001's `refs/heads/WI-000001` no longer
# appeared in `git ls-remote` after this script cancelled it). A new work item
# cuts its own fresh branch regardless, so nothing is left orphaned either way.
#
# Usage:
#   scripts/cancel-work-item.sh --target-org afd360-prod --work-item WI-000001
#   scripts/cancel-work-item.sh -o afd360-prod -w 1fkKa000000KyjGIAS   # by Id
#
# Requires: sf CLI (authenticated to the Hub org) and jq.
#
set -euo pipefail

usage() { sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; }

TARGET_ORG=""
WORK_ITEM=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--target-org) TARGET_ORG="${2:-}"; shift 2 ;;
    -w|--work-item)  WORK_ITEM="${2:-}";  shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$TARGET_ORG" || -z "$WORK_ITEM" ]]; then
  echo "ERROR: --target-org <alias|username> and --work-item <name|id> are required" >&2
  usage; exit 2
fi

command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 3; }

echo "==> Target Hub org: $TARGET_ORG"
USERNAME=$(sf org display --target-org "$TARGET_ORG" --json | jq -r '.result.username')
echo "    connected as: $USERNAME"

# --- Resolve the work item by Name (WI-00000X) or, failing that, by Id ---------
echo "==> Resolving work item: $WORK_ITEM"
REC=$(sf data query --target-org "$TARGET_ORG" --json \
  --query "SELECT Id, Name, Status, Subject FROM WorkItem WHERE Name = '$WORK_ITEM' LIMIT 1" \
  | jq -c '.result.records[0] // empty')

if [[ -z "$REC" ]]; then
  REC=$(sf data query --target-org "$TARGET_ORG" --json \
    --query "SELECT Id, Name, Status, Subject FROM WorkItem WHERE Id = '$WORK_ITEM' LIMIT 1" \
    | jq -c '.result.records[0] // empty')
fi

if [[ -z "$REC" ]]; then
  echo "ERROR: no WorkItem found with Name or Id '$WORK_ITEM' on $TARGET_ORG." >&2
  exit 1
fi

WI_ID=$(jq -r '.Id' <<<"$REC")
WI_NAME=$(jq -r '.Name' <<<"$REC")
WI_STATUS=$(jq -r '.Status' <<<"$REC")
WI_SUBJECT=$(jq -r '.Subject // ""' <<<"$REC")
echo "    $WI_NAME ($WI_ID)  status=$WI_STATUS  subject=\"$WI_SUBJECT\""

# --- Idempotent: already cancelled? -------------------------------------------
if [[ "$WI_STATUS" == "NEVERED" ]]; then
  echo "==> Already NEVERED — nothing to do."
  exit 0
fi

# --- Cancel -------------------------------------------------------------------
echo "==> Setting $WI_NAME to NEVERED ..."
sf data update record --sobject WorkItem --record-id "$WI_ID" \
  --values "Status=NEVERED" --target-org "$TARGET_ORG" >/dev/null

# --- Verify -------------------------------------------------------------------
NEW_STATUS=$(sf data query --target-org "$TARGET_ORG" --json \
  --query "SELECT Status FROM WorkItem WHERE Id = '$WI_ID' LIMIT 1" \
  | jq -r '.result.records[0].Status')

if [[ "$NEW_STATUS" != "NEVERED" ]]; then
  echo "ERROR: expected status NEVERED, got '$NEW_STATUS'. Check the work item manually." >&2
  exit 1
fi

echo "==> Done: $WI_NAME is now NEVERED on $TARGET_ORG."
echo "    Its auto-created Git branch is removed from the remote as part of NEVERED"
echo "    (verify with 'git ls-remote --heads origin $WI_NAME'). Create a new work"
echo "    item to continue; it will cut its own fresh branch."
