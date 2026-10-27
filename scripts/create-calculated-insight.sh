#!/usr/bin/env bash
#
# create-calculated-insight.sh
#
# Create the "Branch Footprint by Region" calculated insight over the Branch_Office__dlm DMO in
# the org where the data kit is built (afd360-dcdev1). Then run it once and show its rows. Add it to
# branch_offices_datakit in the UI afterwards; it's the "update" in the update-only promotion test
# (plan/30-promote.md §8).
#
# The insight: offices per region and country.
#   SELECT COUNT(Branch_Office__dlm.OfficeCode__c) AS office_count__c,
#          Branch_Office__dlm.Region__c AS region__c, Branch_Office__dlm.Country__c AS country__c
#   FROM Branch_Office__dlm GROUP BY region__c, country__c
# Easy to check against data/branch-offices-seed.csv (e.g. West/US = 7). --sql-file overrides it.
#
# What it does (idempotent, self-verifying):
#   1. Pre-flight: org reachable; the DMO exists in the data space with the fields the SQL uses.
#   2. Skip creating if <api-name>__cio already exists (prints its status instead).
#   3. POST /ssot/calculated-insights, then poll until calculatedInsightStatus is ACTIVE.
#   4. --run: POST .../actions/run, poll lastRunStatus, then SELECT the insight's rows (queryv2).
#
# In a target org (staging, prod) use --run-only: it runs the insight the kit deployed and never
# creates one. An insight created by hand isn't owned by the kit, and no kit can update it later
# (KB 003960830), so creating is only for the source org (dcdev1).
#
# Source: Data 360 Connect API reference, "Calculated Insights" (create body: apiName, displayName,
# definitionType, dataSpaceName, expression, publishScheduleInterval). plan/references.md.
#
# Usage:
#   ./scripts/create-calculated-insight.sh -o afd360-dcdev1 --dry-run
#   ./scripts/create-calculated-insight.sh -o afd360-dcdev1 --run
#   ./scripts/create-calculated-insight.sh -o afd360-prod --run-only     # target: run the kit's insight
#
# Requires: sf CLI (authenticated; user has Data 360 Architect) and jq.
#
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
create-calculated-insight.sh — create (and optionally run) the Branch Footprint by Region calculated insight

  -o, --target-org <alias>     Org to create it in (e.g. afd360-dcdev1)
      --api-name <name>        API name without __cio (default branch_footprint_by_region)
      --display-name <label>   Display name (default "Branch Footprint by Region")
      --dataspace <name>       Data space (default default)
      --sql-file <path>        Use this SQL instead of the built-in expression
      --schedule <interval>    publishScheduleInterval (default NotScheduled; e.g. TwentyFour)
      --run                    Run it once after creating, wait, and print its rows
      --run-only               Target orgs: run the existing insight and print its rows; never create
                               (fails if it's missing, e.g. before deploy-datakit-components.sh)
      --dry-run                Pre-flight and print the request body; create nothing
      --wait <sec>             Max time to wait for each status (default 900)
      --api-version <v>        API version (default 64.0)
  -h, --help                   Show this help
EOF
}

TARGET_ORG=""
API_NAME="branch_footprint_by_region"
DISPLAY_NAME="Branch Footprint by Region"
DATASPACE="default"
SQL_FILE=""
SCHEDULE="NotScheduled"
RUN=""
RUN_ONLY=""
DRY_RUN=""
WAIT=900
API_VERSION="64.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--target-org)  TARGET_ORG="${2:-}";   shift 2 ;;
    --api-name)       API_NAME="${2:-}";     shift 2 ;;
    --display-name)   DISPLAY_NAME="${2:-}"; shift 2 ;;
    --dataspace)      DATASPACE="${2:-}";    shift 2 ;;
    --sql-file)       SQL_FILE="${2:-}";     shift 2 ;;
    --schedule)       SCHEDULE="${2:-}";     shift 2 ;;
    --run)            RUN=1;                 shift ;;
    --run-only)       RUN=1; RUN_ONLY=1;     shift ;;
    --dry-run)        DRY_RUN=1;             shift ;;
    --wait)           WAIT="${2:-}";         shift 2 ;;
    --api-version)    API_VERSION="${2:-}";  shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$TARGET_ORG" ]] || { echo "ERROR: --target-org is required" >&2; usage; exit 2; }
[[ "$WAIT" =~ ^[0-9]+$ ]] || { echo "ERROR: --wait must be a number of seconds" >&2; exit 2; }
command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 3; }
API_NAME="${API_NAME%__cio}"
CIO="${API_NAME}__cio"

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH="$REPO_ROOT/tmp-cli-validation/calculated-insights/$TARGET_ORG/$API_NAME"
mkdir -p "$SCRATCH"
BASE="services/data/v${API_VERSION}/ssot"

DMO="Branch_Office__dlm"
if [[ -n "$SQL_FILE" ]]; then
  [[ -f "$SQL_FILE" ]] || { echo "ERROR: --sql-file $SQL_FILE not found" >&2; exit 2; }
  SQL=$(cat "$SQL_FILE")
else
  SQL="SELECT COUNT($DMO.OfficeCode__c) AS office_count__c, $DMO.Region__c AS region__c, $DMO.Country__c AS country__c FROM $DMO GROUP BY region__c, country__c"
fi

echo "==> Calculated insight: $CIO  (\"$DISPLAY_NAME\")"
echo "    Target org: $TARGET_ORG   data space: $DATASPACE   ${DRY_RUN:+(dry-run)}"

# --- 1. Pre-flight --------------------------------------------------------------
sf org display --target-org "$TARGET_ORG" >/dev/null 2>&1 \
  || { echo "ERROR: cannot reach org '$TARGET_ORG' (is it authenticated?)." >&2; exit 1; }

sf api request rest "$BASE/data-model-objects/$DMO" --target-org "$TARGET_ORG" 2>/dev/null > "$SCRATCH/dmo.json" || true
if ! jq -e '.fields' "$SCRATCH/dmo.json" >/dev/null 2>&1; then
  echo "ERROR: DMO $DMO not found in $TARGET_ORG. Response:" >&2; cat "$SCRATCH/dmo.json" >&2; exit 1
fi
MISSING=""
for f in OfficeCode__c Region__c Country__c; do
  jq -e --arg f "$f" '.fields[] | select(.name == $f)' "$SCRATCH/dmo.json" >/dev/null || MISSING+=" $f"
done
[[ -z "$MISSING" ]] || { echo "ERROR: $DMO is missing field(s):$MISSING" >&2; exit 1; }
echo "    DMO $DMO: OK (OfficeCode__c, Region__c, Country__c)"

ci_get() {
  sf api request rest "$BASE/calculated-insights/$CIO" --target-org "$TARGET_ORG" 2>/dev/null > "$SCRATCH/ci.json" || true
  jq -e '.apiName' "$SCRATCH/ci.json" >/dev/null 2>&1
}
ci_field() { jq -r "$1 // empty" "$SCRATCH/ci.json" 2>/dev/null || true; }

# Poll the insight until jq expression $1 yields one of the words in $2 (success) or $3 (failure).
wait_for() {
  local expr="$1" ok="$2" bad="$3" label="$4" deadline=$(( SECONDS + WAIT )) last="" v
  while :; do
    ci_get || true
    v=$(ci_field "$expr")
    [[ "$v" != "$last" ]] && { echo "    $label: ${v:-<none>}"; last="$v"; }
    [[ " $ok " == *" $v "* ]] && return 0
    if [[ -n "$v" && " $bad " == *" $v "* ]]; then
      echo "ERROR: $label is $v. Details ($SCRATCH/ci.json):" >&2
      jq '{calculatedInsightStatus, lastCalcInsightStatusErrorCode, lastRunStatus, lastRunStatusErrorCode}' "$SCRATCH/ci.json" >&2
      return 1
    fi
    [[ $SECONDS -ge $deadline ]] && { echo "ERROR: $label still '${v:-<none>}' after ${WAIT}s." >&2; return 1; }
    sleep 10
  done
}

# --- 2. Already there? ------------------------------------------------------------
EXISTS=""
if ci_get; then
  EXISTS=1
  echo "==> $CIO already exists: status $(ci_field .calculatedInsightStatus), last run $(ci_field .lastRunStatus)"
  [[ "$(ci_field .expression)" == "$SQL" ]] \
    || echo "    note: its expression differs from this script's SQL (edit it in the UI, or delete it to recreate)."
fi

if [[ -z "$EXISTS" && -n "$RUN_ONLY" ]]; then
  echo "ERROR: $CIO doesn't exist in $TARGET_ORG, and --run-only never creates it. In a target org the kit" >&2
  echo "    deploys it: run ./scripts/deploy-datakit-components.sh -k <kit> -o $TARGET_ORG first." >&2
  exit 1
fi

# --- 3. Create ------------------------------------------------------------------------
jq -n --arg api "$API_NAME" --arg dn "$DISPLAY_NAME" --arg ds "$DATASPACE" --arg sql "$SQL" --arg sched "$SCHEDULE" '{
    apiName: $api, displayName: $dn, definitionType: "CALCULATED_METRIC", dataSpaceName: $ds,
    description: "Number of branch offices per region and country (Branch_Office__dlm). Added for the data-kit update-only promotion test.",
    expression: $sql, publishScheduleInterval: $sched }' > "$SCRATCH/create-body.json"

if [[ -n "$DRY_RUN" ]]; then
  echo "==> Dry run: request body for POST /ssot/calculated-insights ($SCRATCH/create-body.json):"
  jq '.' "$SCRATCH/create-body.json"
  exit 0
fi

if [[ -z "$EXISTS" ]]; then
  echo "==> Creating $CIO in $TARGET_ORG ..."
  sf api request rest "$BASE/calculated-insights" --method POST --body "@$SCRATCH/create-body.json" \
    --target-org "$TARGET_ORG" 2>/dev/null > "$SCRATCH/create-response.json" || true
  if ! jq -e '.apiName' "$SCRATCH/create-response.json" >/dev/null 2>&1; then
    echo "ERROR: create failed. Response:" >&2; cat "$SCRATCH/create-response.json" >&2; exit 1
  fi
  echo "    created: $(jq -r '.apiName' "$SCRATCH/create-response.json")  status $(jq -r '.calculatedInsightStatus' "$SCRATCH/create-response.json")"
fi
wait_for .calculatedInsightStatus "ACTIVE" "ERROR FAILED INACTIVE" "status" || exit 1
echo "    dimensions: $(ci_field '[.dimensions[]?.apiName] | join(", ")')"
echo "    measures:   $(ci_field '[.measures[]?.apiName] | join(", ")')"

# --- 4. Run once and show the rows -------------------------------------------------
if [[ -n "$RUN" ]]; then
  echo "==> Running $CIO ..."
  sf api request rest "$BASE/calculated-insights/$CIO/actions/run" --method POST --body '{}' \
    --target-org "$TARGET_ORG" 2>/dev/null > "$SCRATCH/run-response.json" || true
  jq -e 'type == "array" and .[0].errorCode' "$SCRATCH/run-response.json" >/dev/null 2>&1 \
    && { echo "ERROR: run request failed:" >&2; cat "$SCRATCH/run-response.json" >&2; exit 1; }
  wait_for .lastRunStatus "SUCCESS" "FAILURE FAILED ERROR" "last run" || exit 1

  jq -n --arg sql "SELECT region__c, country__c, office_count__c FROM $CIO ORDER BY region__c, country__c" '{sql: $sql}' \
    > "$SCRATCH/query.json"
  sf api request rest "$BASE/queryv2" --method POST --body "@$SCRATCH/query.json" --target-org "$TARGET_ORG" \
    2>/dev/null > "$SCRATCH/rows.json" || true
  if jq -e '.data' "$SCRATCH/rows.json" >/dev/null 2>&1; then
    echo "    rows ($(jq '.data | length' "$SCRATCH/rows.json")); offices total $(jq '[.data[][2] | tonumber] | add' "$SCRATCH/rows.json") (expect 50):"
    jq -r '.data[] | "      \(.[0]) / \(.[1]): \(.[2])"' "$SCRATCH/rows.json"
  else
    echo "    (couldn't query $CIO yet; check Data Explorer → Calculated Insights)"; cat "$SCRATCH/rows.json"
  fi
fi

# A target org got the insight from the kit; the build-and-commit hints below are for the source org.
[[ -n "$RUN_ONLY" ]] && exit 0

cat <<EOF

==> Next (in $TARGET_ORG; plan/30-promote.md §8):
      1. Data Cloud Setup → Data Kits → branch offices datakit → add the calculated insight
         "$DISPLAY_NAME" ($CIO) to the kit.
      2. Publishing Sequence tab: check it lists the insight after the stream bundle. If you edited the
         sequence before, it won't update itself.
      3. Commit the kit to a new work item, e.g.
         ./scripts/commit-datakit-to-work-item.sh -k branch_offices_datakit -s $TARGET_ORG --hub afd360-prod -w WI-000009 --validate-org afd360-dcstaging1 --dry-run
EOF
