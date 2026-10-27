#!/usr/bin/env bash
#
# deploy-datakit-components.sh
#
# Deploy an *installed* Data Cloud **DevOps data kit's components** in a target org:
# turn the kit's templates into the real data streams, DLOs, and DLO→DMO mappings.
#
# Why this exists: getting a kit into a target is two steps.
#   1. Install the kit: the Metadata API deploy (Lifecycle Center's promotion, or
#      scripts/deploy-datakit-cli.sh). This brings the kit definition, its publishing
#      sequence, and its *templates* (DataStreamTemplate, DataKitObjectTemplate,
#      DataSrcDataModelFieldMap, bundle). Nothing runs yet.
#   2. Deploy the kit's components: the kit's Deploy action, i.e. the Connect API
#      POST /ssot/data-kits/<devName>?asyncMode=true (it replaces the older
#      sfdatakit__DeployDataKitComponents flow). This walks the publishing sequence
#      and creates the stream, its DLO, and the mappings in the target.
# Verified 2026-10-26: after WI-000008's promotion, dcstaging1 had the kit with
# templates and publishing sequence, but no branch_offices data stream.
# Source: developer guide "Use the Connect REST API to Deploy Data 360 Data Kits"
# (plan/references.md).
#
# What it does (idempotent, self-verifying):
#   1. Pre-flight: the org is reachable; the kit is installed (GET /ssot/data-kits/<kit>),
#      has a publishing sequence, and its deployment log (DataKitDeploymentLog) so far.
#   2. Compare the publishing sequence with the deployment log and the org. Deploy only if some
#      item was never deployed (e.g. a calculated insight added to the kit later); otherwise skip.
#      Use --force to deploy anyway.
#   3. POST the deploy (async) and capture the jobId.
#   4. Poll GET /ssot/datakit-deployment-job/<jobId> until Complete or Error.
#   5. Verify each stream now exists and that this job deployed every pending item.
#
# Afterwards (manual, plan/30-promote.md §6): streams arrive INACTIVE. For File Upload streams,
# open the stream → Update File → upload the CSV → Deploy; the file never comes with the kit.
#
# Usage:
#   scripts/deploy-datakit-components.sh -k branch_offices_datakit -o afd360-dcstaging1 --dry-run
#   scripts/deploy-datakit-components.sh -k branch_offices_datakit -o afd360-dcstaging1
#   scripts/deploy-datakit-components.sh -k branch_offices_datakit -o afd360-dcstaging1 --job-id <id>   # resume polling
#
# Requires: sf CLI (authenticated to the target org; user has Data 360 Architect) and jq.
#
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
deploy-datakit-components.sh — deploy an installed DevOps data kit's components (streams, DLOs, mappings)

  -k, --data-kit <devName>     Data kit developer name (e.g. branch_offices_datakit)
  -o, --target-org <alias>     Org the kit is installed in (e.g. afd360-dcstaging1)
      --dry-run                Show the kit, its publishing sequence, and which streams exist; don't deploy
      --force                  Deploy even if every publishing-sequence item is already deployed
      --job-id <id>            Don't POST; resume polling an existing deployment job
      --wait <sec>             Max time to poll the job (default 900)
      --api-version <v>        API version (default 64.0)
  -h, --help                   Show this help

Example:
  scripts/deploy-datakit-components.sh -k branch_offices_datakit -o afd360-dcstaging1 --dry-run
EOF
}

DATA_KIT=""
TARGET_ORG=""
DRY_RUN=""
FORCE=""
JOB_ID=""
WAIT=900
API_VERSION="64.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -k|--data-kit)    DATA_KIT="${2:-}";   shift 2 ;;
    -o|--target-org)  TARGET_ORG="${2:-}"; shift 2 ;;
    --dry-run)        DRY_RUN=1;           shift ;;
    --force)          FORCE=1;             shift ;;
    --job-id)         JOB_ID="${2:-}";     shift 2 ;;
    --wait)           WAIT="${2:-}";       shift 2 ;;
    --api-version)    API_VERSION="${2:-}"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$DATA_KIT" || -z "$TARGET_ORG" ]]; then
  echo "ERROR: --data-kit and --target-org are required" >&2
  usage; exit 2
fi
[[ "$WAIT" =~ ^[0-9]+$ ]] || { echo "ERROR: --wait must be a number of seconds" >&2; exit 2; }
command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 3; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH="$REPO_ROOT/tmp-cli-validation/deploy-components/$TARGET_ORG/$DATA_KIT"
mkdir -p "$SCRATCH"
BASE="services/data/v${API_VERSION}/ssot"

echo "==> Data kit:   $DATA_KIT"
echo "    Target org: $TARGET_ORG   ${DRY_RUN:+(dry-run)}"

# --- 1. Pre-flight ------------------------------------------------------------
sf org display --target-org "$TARGET_ORG" >/dev/null 2>&1 \
  || { echo "ERROR: cannot reach org '$TARGET_ORG' (is it authenticated?)." >&2; exit 1; }

sf api request rest "$BASE/data-kits/$DATA_KIT" --target-org "$TARGET_ORG" 2>/dev/null > "$SCRATCH/kit.json" || true
if ! jq -e '.dataKitDetails[0].developerName' "$SCRATCH/kit.json" >/dev/null 2>&1; then
  echo "ERROR: kit $DATA_KIT isn't installed in $TARGET_ORG. Install it first (promotion, or deploy-datakit-cli.sh). Response:" >&2
  cat "$SCRATCH/kit.json" >&2; exit 1
fi
echo "    components:"
jq -r '.dataKitDetails[0].components[] | "      \(.componentType // "DLO/other"): \(.developerName)  (\(.label))"' "$SCRATCH/kit.json"
SEQ_COUNT=$(jq -r '.dataKitDetails[0].publishingSequence // [] | length' "$SCRATCH/kit.json")
if [[ "$SEQ_COUNT" == "0" ]]; then
  echo "ERROR: the kit has no publishing sequence (\"Publishing sequence not defined\")." >&2
  echo "    Define it on the kit in the source org, then re-commit and promote it." >&2
  exit 1
fi
echo "    publishing sequence:"
jq -r '.dataKitDetails[0].publishingSequence | to_entries[] | "      \(.key + 1). \(.value.componentType): \(.value.developerName)"' "$SCRATCH/kit.json"

# The kit's Deployment History tab is backed by DataKitDeploymentLog. No rows means nothing has
# tried to deploy the components yet. A Metadata API install (promotion or CLI) logs none;
# verified 2026-10-26 in dcstaging1.
fetch_deploy_log() {
  sf data query --target-org "$TARGET_ORG" --json --query \
    "SELECT CreatedDate, JobIdentifier, ComponentName, BundleName, DeploymentStatus, DeploymentError FROM DataKitDeploymentLog WHERE DataKitName = '$DATA_KIT' ORDER BY CreatedDate" \
    2>/dev/null > "$SCRATCH/deploy-log.json" || true
  jq -e '.result.records' "$SCRATCH/deploy-log.json" >/dev/null 2>&1
}
# Past jobs, one line each: the kit row's status and the components it logged.
print_deploy_history() {
  fetch_deploy_log || { echo "    deployment history: (couldn't read DataKitDeploymentLog)"; return 0; }
  if [[ "$(jq -r '.result.records | length' "$SCRATCH/deploy-log.json")" == "0" ]]; then
    echo "    deployment history: none (no deploy of this kit has run in $TARGET_ORG. In a target, the"
    echo "      components still need deploying; in the source org that's normal)"
    return 0
  fi
  echo "    deployment history (one line per past job; details in Data Kits → $DATA_KIT → Deployment History):"
  jq -r '.result.records | group_by(.JobIdentifier) | sort_by(.[0].CreatedDate)[]
    | ((map(select(.ComponentName == null))[0].DeploymentStatus) // .[-1].DeploymentStatus) as $st
    | "      \(.[0].CreatedDate[0:16] | sub("T"; " ")) UTC  job \(.[0].JobIdentifier)  \($st): "
      + (map(select(.ComponentName != null) | .ComponentName + (if .DeploymentStatus == "Successful" then "" else " (" + .DeploymentStatus + ")" end)) | join(", "))' \
    "$SCRATCH/deploy-log.json"
}
# One job's rows in full, errors included.
print_job_log() {
  local j="$1"
  fetch_deploy_log || { echo "    (couldn't read DataKitDeploymentLog)"; return 0; }
  echo "==> Deployment log for job $j:"
  jq -r --arg j "$j" '.result.records[] | select((.JobIdentifier // "") | startswith($j[0:15]))
    | "      \(.CreatedDate[11:19])  \(.ComponentName // "(kit)")  \(.DeploymentStatus)\(if .DeploymentError then "  — " + (.DeploymentError | gsub("&quot;"; "\"") | .[0:160]) else "" end)"' \
    "$SCRATCH/deploy-log.json"
}
print_deploy_history

# --- 2. Which of the kit's streams already exist in the target? ---------------
# DataStream has no developer-name column, so match on Name. A kit stream can go by two
# names: its label (the name in the source org, e.g. "branch-offices-seed.csv") or, once the
# kit deploys it, its streamDevName minus the timestamp suffix, which is the DLO's name
# (e.g. "branch_offices_seedcsv"). Verified 2026-10-26 in dcdev1 vs dcstaging1.
STREAMS=$(jq -r '[.dataKitDetails[0].components[] | .streams[]?
  | "\(.label)\t\(.streamDevName | sub("_[0-9]+$"; ""))"] | unique[]' "$SCRATCH/kit.json")
stream_status() {   # prints "<Name>|<status>" for each of the kit's streams that exists in the target
  local IN="" label dev n found
  while IFS=$'\t' read -r label dev; do
    for n in "$label" "$dev"; do
      [[ -n "$n" ]] && IN+="${IN:+,}'${n//\'/\\\'}'"
    done
  done <<<"$STREAMS"
  [[ -n "$IN" ]] || return 0
  found=$({ sf data query --target-org "$TARGET_ORG" --json --query \
      "SELECT Name, DataStreamStatus FROM DataStream WHERE Name IN ($IN)" 2>/dev/null \
    | jq -r '.result.records[]? | "\(.Name)|\(.DataStreamStatus)"'; } || true)
  # one line per kit stream that exists under either name
  while IFS=$'\t' read -r label dev; do
    grep -m1 -F -e "$label|" -e "$dev|" <<<"$found" || true
  done <<<"$STREAMS"
}
EXISTING=$(stream_status)
WANT=$(grep -c . <<<"$STREAMS" || true)
HAVE=$(grep -c . <<<"$EXISTING" || true)
echo "==> Streams in the kit: $WANT; already in $TARGET_ORG: $HAVE"
[[ -n "$EXISTING" ]] && sed 's/^\([^|]*\)|\(.*\)$/      \1: \2/' <<<"$EXISTING"

# --- 2b. Which publishing-sequence items still need deploying? ---------------------
# The deploy walks the whole publishing sequence, so it's needed only if some item hasn't been
# deployed yet, e.g. a calculated insight added to the kit after its first deploy. An item counts
# as deployed if a Successful log row names it as ComponentName or BundleName (a bundle's row
# carries its stream's name, with the bundle in BundleName; a calculated insight's row carries its
# *label*, e.g. "Branch Footprint by Region"; verified 2026-10-27), or if it already exists in the org:
# a bundle whose streams all exist, or a calculated insight that exists. A connection never makes
# a deploy necessary on its own; redeploying it succeeds (verified 2026-10-26 in dcstaging1).
DEPLOYED=$(jq -r '.result.records[]? | select(.DeploymentStatus == "Successful")
  | .ComponentName, .BundleName | select(. != null)' "$SCRATCH/deploy-log.json" 2>/dev/null | sort -u || true)
bundle_streams_exist() {   # all of bundle $1's streams exist in the target?
  local b="$1" label dev
  while IFS=$'\t' read -r label dev; do
    [[ -n "$label$dev" ]] || continue
    grep -q -F -e "$label|" -e "$dev|" <<<"$EXISTING" || return 1
  done < <(jq -r --arg b "$b" '.dataKitDetails[0].components[] | select(.developerName == $b) | .streams[]?
      | "\(.label)\t\(.streamDevName | sub("_[0-9]+$"; ""))"' "$SCRATCH/kit.json")
  return 0
}
ci_exists() {
  local n="${1%__cio}__cio"
  sf api request rest "$BASE/calculated-insights/$n" --target-org "$TARGET_ORG" 2>/dev/null \
    | jq -e '.apiName' >/dev/null 2>&1
}
PENDING=""   # "<position>\t<type>\t<name>\t<label>" for each item that still needs deploying
echo "==> Publishing sequence vs. what's deployed in $TARGET_ORG:"
while IFS=$'\t' read -r pos type name label; do
  state=""
  if grep -qx -F -e "$name" -e "${name%__cio}" -e "${name%__cio}__cio" -e "${label:-$name}" <<<"$DEPLOYED"; then
    state="deployed (log)"
  else
    case "$type" in
      DataConnection)   state="connection (redeploys harmlessly)" ;;
      DataStreamBundle) bundle_streams_exist "$name" && state="exists (streams present, not in log)" ;;
      CalculatedInsight*) ci_exists "$name" && state="exists (not in log)" ;;
    esac
  fi
  if [[ -z "$state" ]]; then
    state="NOT DEPLOYED"
    PENDING+="${pos}"$'\t'"${type}"$'\t'"${name}"$'\t'"${label}"$'\n'
  fi
  echo "      $pos. $type: $name — $state"
done < <(jq -r '.dataKitDetails[0] | .components as $c | .publishingSequence | to_entries[]
    | .value.developerName as $n
    | "\(.key + 1)\t\(.value.componentType)\t\($n)\t\(([$c[] | select(.developerName == $n) | .label][0]) // $n)"' "$SCRATCH/kit.json")
PENDING=${PENDING%$'\n'}
if [[ -n "$PENDING" ]]; then
  echo "    $(grep -c . <<<"$PENDING") item(s) to deploy. The deploy replays the whole sequence; already-deployed"
  echo "      items redeploy in place (verified 2026-10-27). Don't start a second deploy while one is running."
fi

if [[ -n "$DRY_RUN" ]]; then
  echo "==> Dry run: not deploying."
  exit 0
fi
if [[ -z "$JOB_ID" && -z "$FORCE" && -z "$PENDING" ]]; then
  echo "==> Every item in the publishing sequence is already deployed; nothing to do (use --force to redeploy)."
  exit 0
fi

# --- 3. Request the deployment (async) -----------------------------------------
if [[ -z "$JOB_ID" ]]; then
  echo "==> Deploying $DATA_KIT components in $TARGET_ORG ..."
  # The guide documents {"developerName": "<kit>"} for DevOps kits, but v64.0 rejects it
  # (JSON_PARSER_ERROR: Unrecognized field "developerName"); the kit name in the path is
  # enough. The endpoint doesn't exist before v64.0 (NOT_FOUND). Verified 2026-10-26.
  echo '{}' > "$SCRATCH/deploy-body.json"
  sf api request rest "$BASE/data-kits/$DATA_KIT?asyncMode=true" --method POST \
    --body "@$SCRATCH/deploy-body.json" --target-org "$TARGET_ORG" 2>/dev/null > "$SCRATCH/deploy-response.json" || true
  JOB_ID=$(jq -r '.jobId? // empty' "$SCRATCH/deploy-response.json" 2>/dev/null || true)
  if [[ -z "$JOB_ID" ]]; then
    echo "ERROR: deploy request didn't return a jobId. Response:" >&2
    cat "$SCRATCH/deploy-response.json" >&2; exit 1
  fi
  echo "    jobId: $JOB_ID   (resume with --job-id $JOB_ID)"
fi

# --- 4. Poll the job -------------------------------------------------------------
DEADLINE=$(( SECONDS + WAIT ))
LAST=""
while :; do
  sf api request rest "$BASE/datakit-deployment-job/$JOB_ID" --target-org "$TARGET_ORG" 2>/dev/null \
    > "$SCRATCH/job.json" || true
  STATUS=$(jq -r '.jobStatus? // .status? // empty' "$SCRATCH/job.json" 2>/dev/null || true)
  [[ "$STATUS" != "$LAST" ]] && { echo "    job status: ${STATUS:-<unknown>}"; LAST="$STATUS"; }
  case "$STATUS" in
    Complete|Completed|COMPLETE|COMPLETED|Success|SUCCESS) break ;;   # the API returns "Complete"
    Error|ERROR|Failed|FAILED)
      echo "ERROR: deployment job $JOB_ID failed. Details ($SCRATCH/job.json):" >&2
      jq '.' "$SCRATCH/job.json" >&2
      print_job_log "$JOB_ID"
      echo "    Common causes: inactive connection (activate it, then re-run), a component with the" >&2
      echo "    same API name already in the data space, or a data space mismatch." >&2
      exit 1 ;;
  esac
  if [[ $SECONDS -ge $DEADLINE ]]; then
    echo "ERROR: job $JOB_ID still '${STATUS:-<unknown>}' after ${WAIT}s. Re-run with --job-id $JOB_ID to keep polling." >&2
    jq '.' "$SCRATCH/job.json" >&2 2>/dev/null || cat "$SCRATCH/job.json" >&2
    exit 1
  fi
  sleep 10
done

# --- 5. Verify: this job's log, the streams, and every pending item --------------
print_job_log "$JOB_ID"
JOB_FAILED=$(jq -r --arg j "$JOB_ID" '[.result.records[]? | select((.JobIdentifier // "") | startswith($j[0:15]))
    | select(.DeploymentStatus != "Successful") | .ComponentName // "(kit)"] | join(", ")' "$SCRATCH/deploy-log.json")
EXISTING=$(stream_status)
HAVE=$(grep -c . <<<"$EXISTING" || true)
echo "==> Streams in $TARGET_ORG: $HAVE of $WANT"
[[ -n "$EXISTING" ]] && sed 's/^\([^|]*\)|\(.*\)$/      \1: \2/' <<<"$EXISTING"
# Did this job deploy each item that was pending? Log rows name an item by developer name, by its
# stream (BundleName), or, for a calculated insight, by its label.
FAILED_PENDING=""
NEW_CI=""
while IFS=$'\t' read -r pos type name label; do
  [[ -n "$name" ]] || continue
  st=$(jq -r --arg j "$JOB_ID" --arg n "${name%__cio}" --arg l "${label:-$name}" '[.result.records[]? | select((.JobIdentifier // "") | startswith($j[0:15]))
      | select(((.ComponentName // "") | sub("__cio$"; "")) == $n or .ComponentName == $l or (.BundleName // "") == $n) | .DeploymentStatus] | last // "no log row"' \
      "$SCRATCH/deploy-log.json")
  echo "    pending item $pos, $type $name: $st"
  [[ "$st" == "Successful" ]] || FAILED_PENDING+=" $name"
  [[ "$st" == "Successful" && "$type" == CalculatedInsight* ]] && NEW_CI+=" ${name%__cio}__cio"
done <<<"$PENDING"

if [[ "$HAVE" -lt "$WANT" || -n "$FAILED_PENDING" || -n "$JOB_FAILED" ]]; then
  echo "==> RESULT: FAILED (job $JOB_ID)" >&2
  [[ "$HAVE" -lt "$WANT" ]] && echo "    not every stream exists ($HAVE of $WANT)." >&2
  [[ -n "$FAILED_PENDING" ]] && echo "    not deployed by this job:$FAILED_PENDING" >&2
  [[ -n "$JOB_FAILED" ]] && echo "    rows not Successful in this job: $JOB_FAILED (see the log above)" >&2
  exit 1
fi
echo "==> RESULT: SUCCESS. Job $JOB_ID deployed every item${PENDING:+, including the $(grep -c . <<<"$PENDING") pending one(s)}."
if [[ -n "$NEW_CI" ]]; then
  echo "    New calculated insight(s):$NEW_CI. They arrive ACTIVE but never run; run them once"
  echo "    (Calculated Insights → the insight → ▾ → Run Now, or POST …/calculated-insights/<name>/actions/run)."
fi

cat <<EOF

==> Next (in $TARGET_ORG; plan/30-promote.md §6):
      1. Confirm the connection is Active (Data Cloud Setup → Other Connectors).
      2. Data Streams → open the stream. For File Upload: Update File → upload the CSV → Deploy
         (the file never comes with the kit; this activates the stream). Others: activate / Start Ingestion.
      3. Check the DLO → DMO mapping and that the DMO previews data.
EOF
