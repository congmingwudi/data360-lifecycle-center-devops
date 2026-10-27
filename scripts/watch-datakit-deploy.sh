#!/usr/bin/env bash
#
# watch-datakit-deploy.sh
#
# Observe HOW a Data Cloud data kit deploys into a target org during a DevOps
# Center promotion: as a Metadata API deploy, or by running the managed
# sfdatakit__DeployDataKitComponents flow. Implements the three signals in
# plan/30-promote.md §5a. Run against the TARGET org (e.g. afd360-dcstaging1).
#
# Modes:
#   --status   (default) read-only: is the sfdatakit package/flow present? is a
#              debug-log trace flag armed on the deploy user? — the pre-flight picture.
#   --arm      run BEFORE promoting: create/refresh a debug-log trace flag on the
#              deploy user so a log is captured if any Apex/flow runs during the deploy.
#              (Only mutating mode: creates a DebugLevel + TraceFlag via the Tooling API.)
#   --collect  run AFTER promoting: pull the deploy user's recent ApexLogs and grep for
#              the flow; report metadata-path vs. flow-path evidence.
#
# Idempotent and self-verifying; safe to re-run. Only --arm makes changes.
#
# Usage:
#   scripts/watch-datakit-deploy.sh -o afd360-dcstaging1 -u someone@example.com            # --status
#   scripts/watch-datakit-deploy.sh -o afd360-dcstaging1 -u someone@example.com --arm      # before promoting
#   scripts/watch-datakit-deploy.sh -o afd360-dcstaging1 -u someone@example.com --collect  # after promoting
#
# -u/--user is required: the target stage's Lifecycle Center OAuth identity (the user who
# consented to ALMDevOpsConnectedApp in that org, plan/10 §3b step 3). It differs per stage.
#
# Requires: sf CLI (authenticated to the target org) and jq.
#
set -euo pipefail

usage() { sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; }

ORG=""
DEPLOY_USER=""   # required (-u/--user): the stage's Lifecycle Center OAuth identity
MODE="status"
DEBUG_LEVEL="DataKitDeployWatch"   # reusable DebugLevel DeveloperName
TRACE_HOURS=8                      # how long the armed trace flag stays active
# Substrings that mark the flow path in a debug log.
FLOW_MARKERS='sfdatakit|DeployDataKitComponents|FLOW_START_INTERVIEWS'

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--target-org) ORG="${2:-}"; shift 2 ;;
    -u|--user)       DEPLOY_USER="${2:-}"; shift 2 ;;
    --arm)           MODE="arm"; shift ;;
    --collect)       MODE="collect"; shift ;;
    --status)        MODE="status"; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$ORG" ]] || { echo "ERROR: --target-org is required" >&2; usage; exit 2; }
[[ -n "$DEPLOY_USER" ]] || { echo "ERROR: --user is required (the stage's Lifecycle Center OAuth user)" >&2; usage; exit 2; }
command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 3; }

# ---- helpers ---------------------------------------------------------------

# Run a SOQL query; --tool routes to the Tooling API. Echoes the raw --json result.
q() {
  local soql="$1" tooling="${2:-}"
  if [[ "$tooling" == "--tool" ]]; then
    sf data query --target-org "$ORG" --use-tooling-api --json --query "$soql" 2>&1 || true
  else
    sf data query --target-org "$ORG" --json --query "$soql" 2>&1 || true
  fi
}

# Exit if the last query result isn't a clean success (status 0).
ok() { echo "$1" | jq -e '.status == 0' >/dev/null 2>&1; }

# Resolve the deploy user's Id (verifies connectivity + that the user exists).
resolve_user_id() {
  local res id
  res=$(q "SELECT Id, Username FROM User WHERE Username = '$DEPLOY_USER'")
  ok "$res" || { echo "    ✗ query failed: $(echo "$res" | jq -r '.name // .message' 2>/dev/null || echo "$res")" >&2; exit 1; }
  id=$(echo "$res" | jq -r '.result.records[0].Id // empty')
  [[ -n "$id" ]] || { echo "    ✗ user '$DEPLOY_USER' not found in $ORG" >&2; exit 1; }
  echo "$id"
}

# Print whether the sfdatakit package + DeployDataKitComponents flow are present (signal 3).
report_flow_presence() {
  local pkg flow ns active
  # Managed package (namespace sfdatakit) — Tooling API.
  pkg=$(q "SELECT SubscriberPackage.Name, SubscriberPackage.NamespacePrefix FROM InstalledSubscriberPackage" --tool)
  if ok "$pkg" && echo "$pkg" | jq -e '[.result.records[].SubscriberPackage.NamespacePrefix] | index("sfdatakit")' >/dev/null 2>&1; then
    echo "    • sfdatakit package: INSTALLED"
  else
    echo "    • sfdatakit package: not found  → flow path impossible; metadata path confirmed by elimination"
  fi
  # The autolaunched flow itself.
  flow=$(q "SELECT ApiName, Label, IsActive, ProcessType FROM FlowDefinitionView WHERE DeveloperName = 'DeployDataKitComponents'")
  if ok "$flow" && [[ "$(echo "$flow" | jq -r '.result.records | length')" -gt 0 ]]; then
    active=$(echo "$flow" | jq -r '.result.records[0].IsActive')
    ns=$(echo "$flow" | jq -r '.result.records[0].ApiName')
    echo "    • DeployDataKitComponents flow: present ($ns, active=$active)"
  else
    echo "    • DeployDataKitComponents flow: not found via FlowDefinitionView"
  fi
}

# Print any ACTIVE trace flag on the given user Id (signal 2 arming state).
# Only flags whose ExpirationDate is still in the future count as armed.
report_trace_flag() {
  local uid="$1" res n exp now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # SOQL datetime literal (unquoted)
  res=$(q "SELECT Id, ExpirationDate, DebugLevel.DeveloperName FROM TraceFlag WHERE TracedEntityId = '$uid' AND LogType = 'USER_DEBUG' AND ExpirationDate > $now ORDER BY ExpirationDate DESC" --tool)
  ok "$res" || { echo "    • trace flag: could not query TraceFlag"; return; }
  n=$(echo "$res" | jq -r '.result.records | length')
  if [[ "$n" -eq 0 ]]; then
    echo "    • trace flag: none active on $DEPLOY_USER  → run with --arm before promoting"
  else
    exp=$(echo "$res" | jq -r '.result.records[0].ExpirationDate')
    echo "    • trace flag: ACTIVE on $DEPLOY_USER (expires $exp)"
  fi
}

# ---- modes -----------------------------------------------------------------

echo "==> $ORG  (deploy user: $DEPLOY_USER)  [mode: $MODE]"

case "$MODE" in
  status)
    UID_=$(resolve_user_id)
    report_flow_presence
    report_trace_flag "$UID_"
    echo "    ℹ Signal 1 (authoritative): after promoting, check Setup → Deployment Status in $ORG"
    echo "      for a Metadata API deploy listing the data-kit component types (see plan/30 §5a)."
    ;;

  arm)
    UID_=$(resolve_user_id)

    # 1) Ensure the DebugLevel exists (idempotent lookup-or-create). FINEST on
    #    Apex + Workflow is what surfaces the flow; the rest kept modest.
    DL_RES=$(q "SELECT Id FROM DebugLevel WHERE DeveloperName = '$DEBUG_LEVEL'" --tool)
    ok "$DL_RES" || { echo "    ✗ could not query DebugLevel" >&2; exit 1; }
    DL_ID=$(echo "$DL_RES" | jq -r '.result.records[0].Id // empty')
    if [[ -z "$DL_ID" ]]; then
      sf data create record --target-org "$ORG" --use-tooling-api --sobject DebugLevel \
        --values "DeveloperName=$DEBUG_LEVEL MasterLabel=$DEBUG_LEVEL ApexCode=FINEST Workflow=FINEST System=DEBUG Database=INFO Callout=INFO Validation=INFO Visualforce=NONE ApexProfiling=NONE" >/dev/null
      DL_ID=$(q "SELECT Id FROM DebugLevel WHERE DeveloperName = '$DEBUG_LEVEL'" --tool | jq -r '.result.records[0].Id // empty')
      [[ -n "$DL_ID" ]] || { echo "    ✗ failed to create DebugLevel '$DEBUG_LEVEL'" >&2; exit 1; }
      echo "    ✓ created DebugLevel '$DEBUG_LEVEL' ($DL_ID)"
    else
      echo "    ✓ DebugLevel '$DEBUG_LEVEL' already exists ($DL_ID)"
    fi

    # 2) Refresh-or-create the TraceFlag (idempotent: reuse an existing active one).
    START=$(date -u +%Y-%m-%dT%H:%M:%S.000+0000)
    EXPIRE=$(date -u -v+"${TRACE_HOURS}"H +%Y-%m-%dT%H:%M:%S.000+0000)
    TF_ID=$(q "SELECT Id FROM TraceFlag WHERE TracedEntityId = '$UID_' AND LogType = 'USER_DEBUG' AND DebugLevelId = '$DL_ID'" --tool | jq -r '.result.records[0].Id // empty')
    if [[ -n "$TF_ID" ]]; then
      sf data update record --target-org "$ORG" --use-tooling-api --sobject TraceFlag \
        --record-id "$TF_ID" --values "StartDate=$START ExpirationDate=$EXPIRE" >/dev/null
      echo "    ✓ refreshed trace flag ($TF_ID) — active until $EXPIRE"
    else
      sf data create record --target-org "$ORG" --use-tooling-api --sobject TraceFlag \
        --values "TracedEntityId=$UID_ DebugLevelId=$DL_ID LogType=USER_DEBUG StartDate=$START ExpirationDate=$EXPIRE" >/dev/null
      echo "    ✓ armed trace flag on $DEPLOY_USER — active until $EXPIRE"
    fi

    # Self-verify.
    report_trace_flag "$UID_"
    echo "    → Now promote the work item to Staging, then re-run with --collect."
    ;;

  collect)
    UID_=$(resolve_user_id)
    echo "    Recent ApexLogs for $DEPLOY_USER (newest first):"
    LOGS=$(q "SELECT Id, Operation, Status, StartTime, LogLength FROM ApexLog WHERE LogUserId = '$UID_' ORDER BY StartTime DESC LIMIT 25" --tool)
    ok "$LOGS" || { echo "    ✗ could not query ApexLog" >&2; exit 1; }
    N=$(echo "$LOGS" | jq -r '.result.records | length')

    if [[ "$N" -eq 0 ]]; then
      echo "    • no ApexLogs for this user."
      echo "    ⇒ No Apex/flow ran under the trace flag during the deploy window — consistent with a"
      echo "      pure METADATA API deploy (no sfdatakit flow). Confirm the deploy itself in Deployment Status."
    else
      FOUND=0
      while IFS= read -r logid; do
        [[ -n "$logid" ]] || continue
        BODY=$(sf apex log get --target-org "$ORG" --log-id "$logid" 2>/dev/null || true)
        if echo "$BODY" | grep -Eq "$FLOW_MARKERS"; then
          echo "    • $logid: ★ flow markers found (sfdatakit / DeployDataKitComponents)"
          FOUND=1
        else
          echo "    • $logid: no flow markers"
        fi
      done < <(echo "$LOGS" | jq -r '.result.records[].Id')

      if [[ "$FOUND" -eq 1 ]]; then
        echo "    ⇒ FLOW PATH: the deploy invoked sfdatakit__DeployDataKitComponents. Record this in plan/30 §7."
      else
        echo "    ⇒ Logs exist but none show the data-kit flow — consistent with the METADATA API path."
      fi
    fi
    echo "    ℹ Pair this with Setup → Deployment Status (signal 1) for the authoritative deploy record."
    ;;
esac
