#!/usr/bin/env bash
#
# commit-datakit-to-work-item.sh
#
# Commit a Data Cloud **Data Kit** from the dev sandbox onto a Lifecycle Center
# (DevOps Center) **work-item branch** yourself, the way Lifecycle Center's own
# commit would have, so the work item can then be promoted through the pipeline
# in the Lifecycle Center UI.
#
# Why this exists: the DX Inspector commit fails for data-kit metadata. The
# components stage fine (COMMIT_COMPONENT = SUCCESS, and the Hub records them as
# WorkItemComponent rows), but the final step that pushes to Git fails
# (COMMIT_COMPLETED = FAIL), so the WI-* branch never moves (plan/30-promote.md §3).
# This script does that last step from the CLI.
#
# What a *successful* Lifecycle Center commit looks like (observed on the control
# work item WI-000002 in the sfdx-devopscenter-test-pipeline repo), mirrored here:
#   - Source format (decomposed), under force-app/main/default/.
#   - One commit on the work-item branch (WI-00000N, no prefix); the commit
#     message is exactly the comment you'd type in DX Inspector.
#   - Author "DevOps Center <noreply@salesforce.com>". This script defaults to *your*
#     git identity instead (honest history); pass --author to mimic Lifecycle Center.
#   - Afterward, the Hub's WorkItemComponentList row for that commit carries
#     CommitReference (SHA), CommitDate, and CommitMessage. For a pushed branch,
#     Lifecycle Center writes that row itself by *inspecting* the branch (verified
#     WI-000007/8, a few seconds after the push), so no DX Inspector commit is needed.
#
# What it does (idempotent, self-verifying):
#   1. Pre-flight: orgs reachable; the work item exists on the Hub and is IN_PROGRESS;
#      its branch exists on the remote.
#   2. Fetch the kit manifest from the dev org (GET /ssot/datakit/<devName>/manifest)
#      and build a package.xml.
#   3. Check out the work-item branch in an isolated git worktree under
#      tmp-cli-validation/wi-commit/<WI>/ (your main checkout is never touched).
#   4. Retrieve the kit in SOURCE format into that worktree's force-app/.
#   5. Drop the non-deployable Key Qualifier (KQ_*) field file(s); otherwise the
#      Staging promotion deploy fails ("Key Qualifier Field cannot be deployed
#      using Data Kits", KB 005224006). Raise sfdx-project.json sourceApiVersion
#      to --api-version if lower (at 62.0 the kit source won't deploy).
#      --validate-org: check-only deploy to the next stage's org before pushing.
#   6. Commit (skipped if the branch already has exactly this content), then push
#      fast-forward only (never force), then verify the remote SHA.
#   7. Wait for Lifecycle Center's inspection (the WorkItemComponentList whose
#      CommitReference is the pushed SHA) and check it lists exactly the kit members
#      the commit changed. Members already on the stage branch aren't expected there.
#   8. --record-commit (fallback only): if no inspected list appears, write
#      CommitReference/CommitDate/CommitMessage onto the work item's latest
#      uncommitted WorkItemComponentList row.
#
# Usage:
#   scripts/commit-datakit-to-work-item.sh -k branch_offices_test_datakit \
#       -s afd360-dcdev1 --hub afd360-prod -w WI-000007 --dry-run
#   scripts/commit-datakit-to-work-item.sh -k branch_offices_test_datakit \
#       -s afd360-dcdev1 --hub afd360-prod -w WI-000007 --validate-org afd360-dcstaging1 [--record-commit]
#
# Requires: sf CLI (authenticated to the dev org and the Hub), git with push access
# to the pipeline repo, and jq.
#
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
commit-datakit-to-work-item.sh — commit a data kit to a Lifecycle Center work-item branch via the CLI

  -k, --data-kit <devName>     Data kit developer name (e.g. branch_offices_test_datakit)
  -s, --source-org <alias>     Dev org the kit is built in (e.g. afd360-dcdev1)
      --hub <alias>            Lifecycle Center Hub org (e.g. afd360-prod)
  -w, --work-item <WI-name>    Work item, e.g. WI-000007; its branch has the same name
  -m, --message <text>         Commit message (= the DX Inspector comment). Default derived from the kit.
      --author <"Name <email>">  Commit author (default: your git user.name/user.email)
      --remote <name>          Git remote of the pipeline repo (default: origin)
      --validate-org <alias>   Check-only deploy of the commit to this org (next stage) before pushing
      --inspect-wait <sec>     How long to wait for Lifecycle Center to inspect the push (default 120)
      --record-commit          Fallback: if no inspection appears, write the SHA/date/message onto
                               the Hub's latest uncommitted WorkItemComponentList row
      --dry-run                Build the commit locally in the worktree; don't push or touch the Hub
      --api-version <v>        API version for manifest + retrieve (default 64.0)
  -h, --help                   Show this help

Example:
  scripts/commit-datakit-to-work-item.sh -k branch_offices_test_datakit -s afd360-dcdev1 \
      --hub afd360-prod -w WI-000007 --dry-run
EOF
}

DATA_KIT=""
SOURCE_ORG=""
HUB_ORG=""
WORK_ITEM=""
MESSAGE=""
AUTHOR=""
REMOTE="origin"
INSPECT_WAIT=120
RECORD_COMMIT=""
VALIDATE_ORG=""
DRY_RUN=""
API_VERSION="64.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -k|--data-kit)    DATA_KIT="${2:-}";   shift 2 ;;
    -s|--source-org)  SOURCE_ORG="${2:-}"; shift 2 ;;
    --hub)            HUB_ORG="${2:-}";    shift 2 ;;
    -w|--work-item)   WORK_ITEM="${2:-}";  shift 2 ;;
    -m|--message)     MESSAGE="${2:-}";    shift 2 ;;
    --author)         AUTHOR="${2:-}";     shift 2 ;;
    --remote)         REMOTE="${2:-}";     shift 2 ;;
    --validate-org)   VALIDATE_ORG="${2:-}"; shift 2 ;;
    --inspect-wait)   INSPECT_WAIT="${2:-}"; shift 2 ;;
    --record-commit)  RECORD_COMMIT=1;     shift ;;
    --dry-run)        DRY_RUN=1;           shift ;;
    --api-version)    API_VERSION="${2:-}"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$DATA_KIT" || -z "$SOURCE_ORG" || -z "$HUB_ORG" || -z "$WORK_ITEM" ]]; then
  echo "ERROR: --data-kit, --source-org, --hub and --work-item are all required" >&2
  usage; exit 2
fi
[[ "$WORK_ITEM" =~ ^WI-[0-9]+$ ]] || { echo "ERROR: --work-item must look like WI-000007" >&2; exit 2; }
[[ -n "$MESSAGE" ]] || MESSAGE="$DATA_KIT data kit (CLI commit; DX Inspector commit fails for data kits)"

command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 3; }

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Step 3 deletes and re-creates the worktree; if we were launched from inside it,
# our cwd would vanish and every later sf call fails (Node's process.cwd() ENOENT).
cd "$REPO_ROOT"
if [[ -z "$AUTHOR" ]]; then
  GIT_NAME=$(git config user.name || true); GIT_EMAIL=$(git config user.email || true)
  [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]] \
    || { echo "ERROR: no git user.name/user.email configured; set them or pass --author." >&2; exit 2; }
  AUTHOR="$GIT_NAME <$GIT_EMAIL>"
fi
[[ "$INSPECT_WAIT" =~ ^[0-9]+$ ]] || { echo "ERROR: --inspect-wait must be a number of seconds" >&2; exit 2; }
BRANCH="$WORK_ITEM"   # Lifecycle Center names the branch after the work item (verified: refs/heads/WI-000001)
SCRATCH="$REPO_ROOT/tmp-cli-validation/wi-commit/$WORK_ITEM"
WT="$SCRATCH/worktree"

# One run per work item at a time: step 3 deletes and re-creates the shared worktree, which
# breaks a concurrent run ("fatal: cannot change to …/worktree"; seen 2026-10-27). A stale lock
# (its PID is gone) is taken over.
mkdir -p "$SCRATCH"
LOCK="$SCRATCH/.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  OTHER=$(cat "$LOCK/pid" 2>/dev/null || true)
  if [[ -n "$OTHER" ]] && kill -0 "$OTHER" 2>/dev/null; then
    echo "ERROR: another run for $WORK_ITEM is in progress (PID $OTHER). Wait for it, then re-run." >&2
    exit 1
  fi
  echo "    (taking over a stale lock from PID ${OTHER:-unknown})"
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

echo "==> Data kit:   $DATA_KIT"
echo "    Source org: $SOURCE_ORG"
echo "    Hub:        $HUB_ORG"
echo "    Work item:  $WORK_ITEM  (branch $REMOTE/$BRANCH)   ${DRY_RUN:+(dry-run)}"
echo "    Worktree:   $WT"

# --- 1. Pre-flight ------------------------------------------------------------
for ORG in "$SOURCE_ORG" "$HUB_ORG" ${VALIDATE_ORG:+"$VALIDATE_ORG"}; do
  sf org display --target-org "$ORG" >/dev/null 2>&1 \
    || { echo "ERROR: cannot reach org '$ORG' (is it authenticated?)." >&2; exit 1; }
done

WI_JSON=$(sf data query --target-org "$HUB_ORG" --json \
  --query "SELECT Id, Name, Status, Subject FROM WorkItem WHERE Name = '$WORK_ITEM'" 2>/dev/null)
WI_ID=$(jq -r '.result.records[0].Id // empty' <<<"$WI_JSON")
WI_STATUS=$(jq -r '.result.records[0].Status // empty' <<<"$WI_JSON")
[[ -n "$WI_ID" ]] || { echo "ERROR: work item $WORK_ITEM not found on $HUB_ORG." >&2; exit 1; }
echo "    Hub record: $WORK_ITEM is $WI_STATUS — $(jq -r '.result.records[0].Subject' <<<"$WI_JSON")"
if [[ "$WI_STATUS" != "IN_PROGRESS" ]]; then
  echo "ERROR: $WORK_ITEM is $WI_STATUS; Lifecycle Center only commits to In Progress work items." >&2
  echo "    Mark it In Progress in Lifecycle Center first (plan/30-promote.md §2)." >&2
  exit 1
fi

git -C "$REPO_ROOT" fetch --quiet "$REMOTE" \
  || { echo "ERROR: git fetch $REMOTE failed." >&2; exit 1; }
git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/remotes/$REMOTE/$BRANCH" >/dev/null \
  || { echo "ERROR: branch $BRANCH not found on $REMOTE (Lifecycle Center creates it at In Progress)." >&2; exit 1; }
BASE_SHA=$(git -C "$REPO_ROOT" rev-parse "refs/remotes/$REMOTE/$BRANCH")
echo "    Branch tip: $BASE_SHA"

# --- 2. Fetch manifest + build package.xml ------------------------------------
rm -rf "$SCRATCH/manifest.json" "$SCRATCH/package.xml"
mkdir -p "$SCRATCH"
echo "==> Fetching kit manifest from $SOURCE_ORG ..."
sf api request rest "services/data/v${API_VERSION}/ssot/datakit/${DATA_KIT}/manifest" \
  --target-org "$SOURCE_ORG" 2>/dev/null > "$SCRATCH/manifest.json"

if ! jq -e '.dataKitMembers | length > 0' "$SCRATCH/manifest.json" >/dev/null 2>&1; then
  echo "ERROR: manifest fetch returned no dataKitMembers. Response was:" >&2
  cat "$SCRATCH/manifest.json" >&2
  echo "    (Check the --data-kit dev name and --api-version.)" >&2
  exit 1
fi
MEMBER_COUNT=$(jq -r '[.dataKitMembers[].developerName | length] | add' "$SCRATCH/manifest.json")
echo "    manifest OK — $MEMBER_COUNT members across $(jq -r '.dataKitMembers | length' "$SCRATCH/manifest.json") types"

{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<Package xmlns="http://soap.sforce.com/2006/04/metadata">'
  jq -r '.dataKitMembers[] | "    <types>\n" + (.developerName | map("        <members>\(.)</members>") | join("\n")) + "\n        <name>\(.entityName)</name>\n    </types>"' "$SCRATCH/manifest.json"
  echo "    <version>${API_VERSION}</version>"
  echo '</Package>'
} > "$SCRATCH/package.xml"

# --- 3. Isolated worktree on the work-item branch -----------------------------
# Re-create from the remote tip every run (idempotent). -B resets the local branch
# to the remote, so a previous unpushed --dry-run commit is discarded.
if [[ -e "$WT" ]]; then
  git -C "$REPO_ROOT" worktree remove --force "$WT" 2>/dev/null || rm -rf "$WT"
fi
git -C "$REPO_ROOT" worktree prune
git -C "$REPO_ROOT" worktree add --quiet -B "$BRANCH" "$WT" "refs/remotes/$REMOTE/$BRANCH"
git -C "$WT" branch --quiet --set-upstream-to="$REMOTE/$BRANCH" "$BRANCH"

# --- 4. Retrieve in source format into the worktree ---------------------------
echo "==> Retrieving kit (source format) from $SOURCE_ORG into $BRANCH ..."
( cd "$WT" && sf project retrieve start --manifest "$SCRATCH/package.xml" \
    --target-org "$SOURCE_ORG" --api-version "$API_VERSION" --ignore-conflicts --json ) \
  > "$SCRATCH/retrieve.json" 2>/dev/null || true
if [[ "$(jq -r '.status // 1' "$SCRATCH/retrieve.json" 2>/dev/null)" != "0" ]]; then
  echo "ERROR: retrieve failed. Output: $SCRATCH/retrieve.json" >&2
  jq -r '.message // empty' "$SCRATCH/retrieve.json" >&2 2>/dev/null || true
  exit 1
fi
echo "    retrieved $(jq -r '.result.files | length' "$SCRATCH/retrieve.json") file(s)"

# --- 5. Drop non-deployable Key Qualifier (KQ_) fields ------------------------
# In source format the KQ_ field is its own fields/KQ_*.field-meta.xml file (in
# metadata format it rode inline in the .object; see deploy-datakit-cli.sh).
STRIPPED=0
while IFS= read -r -d '' F; do
  if [[ "$(basename "$F")" == KQ_* ]] || grep -q '<usageTag>KeyQualifier</usageTag>' "$F"; then
    rm -f "$F"; STRIPPED=$(( STRIPPED + 1 ))
    echo "    removed Key Qualifier field: ${F#"$WT"/}"
  fi
done < <(find "$WT/force-app" -path '*/fields/*.field-meta.xml' -print0)
echo "==> Stripped $STRIPPED Key Qualifier field file(s)."

# --- 5b. sourceApiVersion must be new enough for the data-kit source -----------
# The promotion deploys the branch at the project's sourceApiVersion. At 62.0 the
# Staging deploy fails ("Property 'useDeterministicNaming' not valid in version
# 62.0"; verified 2026-10-26), so raise it, and commit it alongside the kit.
CUR_API=$(jq -r '.sourceApiVersion // "0"' "$WT/sfdx-project.json")
if awk -v a="$CUR_API" -v b="$API_VERSION" 'BEGIN { exit !(a + 0 < b + 0) }'; then
  sed -i.bak "s/\"sourceApiVersion\": *\"$CUR_API\"/\"sourceApiVersion\": \"$API_VERSION\"/" "$WT/sfdx-project.json"
  rm -f "$WT/sfdx-project.json.bak"
  [[ "$(jq -r '.sourceApiVersion' "$WT/sfdx-project.json")" == "$API_VERSION" ]] \
    || { echo "ERROR: could not set sourceApiVersion in sfdx-project.json" >&2; exit 1; }
  echo "==> Raised sfdx-project.json sourceApiVersion $CUR_API -> $API_VERSION."
fi

# --- 5c. Optional: validate the commit contents against the next stage's org ----
# Same Metadata API deploy the promotion runs, as check-only. Blocks the push on failure.
if [[ -n "$VALIDATE_ORG" ]]; then
  echo "==> Validating against $VALIDATE_ORG (check-only, no changes) ..."
  set +e
  VAL_JSON=$( cd "$WT" && sf project deploy start --source-dir force-app --target-org "$VALIDATE_ORG" \
    --dry-run --wait 30 --json 2>/dev/null )
  set -e
  if [[ "$(jq -r '.result.success // false' <<<"$VAL_JSON" 2>/dev/null)" != "true" ]]; then
    echo "ERROR: validation against $VALIDATE_ORG failed; not committing/pushing." >&2
    jq -r '.result.details.componentFailures[]? | "      \(.componentType) \(.fullName): \(.problem)"' <<<"$VAL_JSON" >&2 2>/dev/null \
      || jq -r '.message // empty' <<<"$VAL_JSON" >&2 2>/dev/null || true
    exit 1
  fi
  echo "    validation OK — $(jq -r '.result.numberComponentsDeployed' <<<"$VAL_JSON")/$(jq -r '.result.numberComponentsTotal' <<<"$VAL_JSON") components"
fi

# --- 6. Commit, push, verify --------------------------------------------------
git -C "$WT" add -A force-app sfdx-project.json
if git -C "$WT" diff --cached --quiet; then
  echo "==> $BRANCH already contains exactly this kit source; nothing to commit."
  COMMIT_SHA="$BASE_SHA"
  NEW_COMMIT=""
else
  echo "==> Files in the commit:"
  git -C "$WT" diff --cached --name-status | sed 's/^/      /'
  git -C "$WT" commit --quiet --author="$AUTHOR" -m "$MESSAGE"
  COMMIT_SHA=$(git -C "$WT" rev-parse HEAD)
  NEW_COMMIT=1
  echo "    committed $COMMIT_SHA  (author: $AUTHOR)"
fi

if [[ -n "$DRY_RUN" ]]; then
  echo "==> Dry run: not pushing. Inspect with: git -C \"$WT\" show --stat"
else
  if [[ -n "$NEW_COMMIT" ]]; then
    echo "==> Pushing $BRANCH to $REMOTE (fast-forward only) ..."
    git -C "$WT" push --quiet "$REMOTE" "HEAD:refs/heads/$BRANCH" \
      || { echo "ERROR: push rejected (branch moved on $REMOTE?). Re-run to rebuild on the new tip." >&2; exit 1; }
  fi
  REMOTE_SHA=$(git -C "$REPO_ROOT" ls-remote "$REMOTE" "refs/heads/$BRANCH" | cut -f1)
  if [[ "$REMOTE_SHA" == "$COMMIT_SHA" ]]; then
    echo "    verified: $REMOTE/$BRANCH = $REMOTE_SHA"
  else
    echo "ERROR: $REMOTE/$BRANCH is $REMOTE_SHA, expected $COMMIT_SHA." >&2; exit 1
  fi
fi

# --- 7. Wait for Lifecycle Center's inspection of the push, then check it ------
# After a push, Lifecycle Center inspects the branch and creates a
# WorkItemComponentList whose CommitReference is the pushed SHA (verified WI-000007/8,
# a few seconds after the push). It lists what the commit changed vs. its parent, so
# the expected set is the kit members whose retrieved files are in that diff. Members
# already on the stage branch (e.g. a DMO promoted with an earlier work item) aren't.
wicl_for_sha() {
  sf data query --target-org "$HUB_ORG" --json --query \
    "SELECT Id, Name FROM WorkItemComponentList WHERE WorkItemId = '$WI_ID' AND CommitReference = '$COMMIT_SHA' LIMIT 1" \
    2>/dev/null | jq -r '.result.records[0] // empty | "\(.Id) \(.Name)"'
}

INSPECTED=""
if [[ -n "$DRY_RUN" ]]; then
  echo "==> Dry run: nothing pushed, so no Lifecycle Center inspection to check."
else
  [[ -n "$NEW_COMMIT" ]] && echo "==> Waiting up to ${INSPECT_WAIT}s for Lifecycle Center to inspect $BRANCH ..."
  DEADLINE=$(( SECONDS + INSPECT_WAIT ))
  while :; do
    INSPECTED=$(wicl_for_sha)
    # Without a new push there's nothing new to inspect, so look once.
    [[ -n "$INSPECTED" || -z "$NEW_COMMIT" || $SECONDS -ge $DEADLINE ]] && break
    sleep 5
  done
fi

if [[ -n "$INSPECTED" ]]; then
  read -r WICL_ID WICL_NAME <<<"$INSPECTED"
  echo "    inspected: $WICL_NAME (CommitReference = $COMMIT_SHA)"
  sf data query --target-org "$HUB_ORG" --json --query \
    "SELECT MemberType, MemberName FROM WorkItemComponent WHERE WorkItemComponentListId = '$WICL_ID'" \
    2>/dev/null > "$SCRATCH/hub-components.json"
  git -C "$WT" diff --name-only "$COMMIT_SHA^" "$COMMIT_SHA" > "$SCRATCH/changed-files.txt"
  echo "==> $WICL_NAME vs. the kit members this commit changed:"
  jq -r -n --arg wt "$WT/" --argjson total "$MEMBER_COUNT" \
    --rawfile changed "$SCRATCH/changed-files.txt" \
    --slurpfile r "$SCRATCH/retrieve.json" --slurpfile h "$SCRATCH/hub-components.json" '
    ($changed | split("\n") | map(select(length > 0))) as $files
    | ([$r[0].result.files[] | select(.filePath | ltrimstr($wt) | IN($files[]))
        | "\(.type):\(.fullName)"] | unique) as $exp
    | ([$h[0].result.records[] | "\(.MemberType):\(.MemberName)"] | unique) as $hub
    | "      changed in commit: \($exp | length) of \($total) kit members (the rest were already on the branch)",
      "      on the Hub:        \($hub | length); in both: \(($exp - ($exp - $hub)) | length)",
      (($exp - $hub)[] | "      missing on Hub:    \(.)"),
      (($hub - $exp)[] | "      Hub only:          \(.)"),
      (if $exp == $hub then "      OK: the Change List matches the commit." else empty end)'
elif [[ -z "$DRY_RUN" ]]; then
  if [[ -z "$NEW_COMMIT" ]]; then
    echo "==> No new commit, and no Lifecycle Center component list references $COMMIT_SHA."
    echo "    If $BRANCH has no commit of its own, its stage branch already contains exactly this"
    echo "    kit, so this work item has nothing to promote."
  else
    echo "WARN: Lifecycle Center hasn't inspected $COMMIT_SHA within ${INSPECT_WAIT}s." >&2
  fi

  # --- 8. Fallback: record the commit on the Hub, as Lifecycle Center's finalize step would --
  if [[ -n "$RECORD_COMMIT" ]]; then
    WICL_JSON=$(sf data query --target-org "$HUB_ORG" --json --query \
      "SELECT Id, Name, CommitReference FROM WorkItemComponentList WHERE WorkItemId = '$WI_ID' ORDER BY CreatedDate DESC LIMIT 1" 2>/dev/null)
    WICL_ID=$(jq -r '.result.records[0].Id // empty' <<<"$WICL_JSON")
    WICL_NAME=$(jq -r '.result.records[0].Name // empty' <<<"$WICL_JSON")
    WICL_REF=$(jq -r '.result.records[0].CommitReference // empty' <<<"$WICL_JSON")
    if [[ -z "$WICL_ID" ]]; then
      echo "    --record-commit: $WORK_ITEM has no component list on the Hub to record onto." >&2
    elif [[ -n "$WICL_REF" ]]; then
      echo "    --record-commit: $WICL_NAME already references commit $WICL_REF; leaving it unchanged." >&2
    else
      NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
      jq -n --arg r "$COMMIT_SHA" --arg d "$NOW" --arg m "$MESSAGE" \
        '{CommitReference:$r, CommitDate:$d, CommitMessage:$m}' > "$SCRATCH/wicl-patch.json"
      sf api request rest "services/data/v${API_VERSION}/sobjects/WorkItemComponentList/$WICL_ID" \
        --method PATCH --body "@$SCRATCH/wicl-patch.json" --target-org "$HUB_ORG" >/dev/null 2>&1 \
        || { echo "ERROR: could not update $WICL_NAME on $HUB_ORG." >&2; exit 1; }
      [[ -n "$(wicl_for_sha)" ]] \
        || { echo "ERROR: $WICL_NAME CommitReference didn't take $COMMIT_SHA." >&2; exit 1; }
      echo "    recorded on Hub: $WICL_NAME CommitReference = $COMMIT_SHA"
    fi
  elif [[ -n "$NEW_COMMIT" ]]; then
    echo "    Refresh $WORK_ITEM in Lifecycle Center. If its Change List stays empty, re-run with --record-commit." >&2
  fi
fi

cat <<EOF

==> Next (Lifecycle Center UI, Hub org; plan/30-promote.md §3e):
      1. Open $WORK_ITEM: its Change List should show the inspected components.
      2. Move it to In Review (opens the PR $BRANCH → the Staging branch).
      3. Ready to Promote → Promote to Staging, then do the §6 runtime wiring in the target.
EOF
