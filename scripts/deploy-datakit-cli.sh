#!/usr/bin/env bash
#
# deploy-datakit-cli.sh
#
# Deploy a Data Cloud **Data Kit** from a source org to a target org via the
# *supported* CLI / Metadata-API manifest path — the path Salesforce documents
# for moving DevOps-type data kits (CLI or change sets).
#
# Why this exists: DevOps Center's own commit step (DX Inspector) CANNOT carry
# Data Cloud data-kit metadata — it stages the components then fails at finalize
# with a generic "Commit failed during processing" (root cause + evidence in
# plan/30-promote.md §3). Salesforce documents the CLI and change sets, not
# DevOps Center / DX Inspector, as the ways to move a data kit. So the data kit
# takes this CLI path instead; ordinary metadata still goes through DevOps Center.
#
# What it does (idempotent, self-verifying):
#   1. Fetch the kit manifest from the SOURCE org (Connect REST
#      GET /ssot/datakit/<devName>/manifest) and build a package.xml.
#   2. Retrieve the kit in metadata format into a scratch dir (NOT force-app/).
#   3. Strip the non-deployable Key Qualifier (KQ_) field(s) from the retrieved
#      DMO object(s) — the one manual fix Salesforce documents ("don't skip it").
#   4. Deploy to the TARGET org (use --dry-run to validate only).
#   5. On a real deploy, verify the kit is present in the target.
#
# Scratch files land under <repo>/tmp-cli-validation/<kit>/ (untracked).
#
# Data Cloud RUNTIME wiring is still needed in the target afterward (plan/30 §6): activate the
# UploadedFiles connection if it's inactive, run scripts/deploy-datakit-components.sh (installing
# doesn't create the streams/DLOs/mappings), then Update File once to activate the stream.
#
# Usage:
#   scripts/deploy-datakit-cli.sh --data-kit branch_offices_datakit \
#       --source-org afd360-dcdev1 --target-org afd360-dcstaging1 [--dry-run]
#   scripts/deploy-datakit-cli.sh -k <devName> -s <srcAlias> -o <tgtAlias> [--dry-run] [--api-version 64.0]
#
# Requires: sf CLI (authenticated to BOTH orgs) and jq.
#
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
deploy-datakit-cli.sh — deploy a Data Cloud data kit via the supported CLI manifest path

  -k, --data-kit <devName>     Data kit developer name (e.g. branch_offices_datakit)
  -s, --source-org <alias>     Org to retrieve the kit FROM (the dev sandbox)
  -o, --target-org <alias>     Org to deploy the kit TO (staging / prod)
      --dry-run                Validate the deploy only; change nothing in the target
      --api-version <v>        API version for the manifest/retrieve (default 64.0)
  -h, --help                   Show this help

Example:
  scripts/deploy-datakit-cli.sh -k branch_offices_datakit -s afd360-dcdev1 -o afd360-dcstaging1 --dry-run
EOF
}

DATA_KIT=""
SOURCE_ORG=""
TARGET_ORG=""
DRY_RUN=""
API_VERSION="64.0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -k|--data-kit)    DATA_KIT="${2:-}";   shift 2 ;;
    -s|--source-org)  SOURCE_ORG="${2:-}"; shift 2 ;;
    -o|--target-org)  TARGET_ORG="${2:-}"; shift 2 ;;
    --dry-run)        DRY_RUN="--dry-run"; shift ;;
    --api-version)    API_VERSION="${2:-}"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$DATA_KIT" || -z "$SOURCE_ORG" || -z "$TARGET_ORG" ]]; then
  echo "ERROR: --data-kit, --source-org and --target-org are all required" >&2
  usage; exit 2
fi

command -v jq >/dev/null || { echo "ERROR: jq is required" >&2; exit 3; }

# Resolve repo root so scratch files land under <repo>/tmp-cli-validation regardless of CWD.
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKDIR="$REPO_ROOT/tmp-cli-validation/$DATA_KIT"

echo "==> Data kit:   $DATA_KIT"
echo "    Source org: $SOURCE_ORG"
echo "    Target org: $TARGET_ORG   ${DRY_RUN:+(dry-run)}"
echo "    Work dir:   $WORKDIR"

# --- Connectivity -------------------------------------------------------------
for ORG in "$SOURCE_ORG" "$TARGET_ORG"; do
  sf org display --target-org "$ORG" >/dev/null 2>&1 \
    || { echo "ERROR: cannot reach org '$ORG' (is it authenticated?)." >&2; exit 1; }
done

# --- Clean scratch dir (idempotent) ------------------------------------------
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

# --- 1. Fetch manifest + build package.xml -----------------------------------
echo "==> Fetching kit manifest from $SOURCE_ORG ..."
sf api request rest "services/data/v${API_VERSION}/ssot/datakit/${DATA_KIT}/manifest" \
  --target-org "$SOURCE_ORG" 2>/dev/null > "$WORKDIR/manifest.json"

if ! jq -e '.dataKitMembers | length > 0' "$WORKDIR/manifest.json" >/dev/null 2>&1; then
  echo "ERROR: manifest fetch returned no dataKitMembers. Response was:" >&2
  cat "$WORKDIR/manifest.json" >&2
  echo "    (Check the --data-kit dev name and --api-version.)" >&2
  exit 1
fi

MEMBER_COUNT=$(jq -r '[.dataKitMembers[].developerName | length] | add' "$WORKDIR/manifest.json")
TYPE_COUNT=$(jq -r '.dataKitMembers | length' "$WORKDIR/manifest.json")
echo "    manifest OK — $MEMBER_COUNT members across $TYPE_COUNT types"

{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<Package xmlns="http://soap.sforce.com/2006/04/metadata">'
  jq -r '.dataKitMembers[] | "    <types>\n" + (.developerName | map("        <members>\(.)</members>") | join("\n")) + "\n        <name>\(.entityName)</name>\n    </types>"' "$WORKDIR/manifest.json"
  echo "    <version>${API_VERSION}</version>"
  echo '</Package>'
} > "$WORKDIR/package.xml"

# --- 2. Retrieve (metadata format, into scratch dir) -------------------------
echo "==> Retrieving kit metadata from $SOURCE_ORG ..."
sf project retrieve start --manifest "$WORKDIR/package.xml" \
  --target-metadata-dir "$WORKDIR/mdapi" --unzip --target-org "$SOURCE_ORG" >/dev/null

MDROOT=$(dirname "$(find "$WORKDIR/mdapi" -name package.xml | head -1)")
[[ -n "$MDROOT" && -d "$MDROOT" ]] || { echo "ERROR: retrieved metadata root not found under $WORKDIR/mdapi" >&2; exit 1; }
echo "    retrieved to: $MDROOT"

# --- 3. Strip non-deployable Key Qualifier (KQ_) fields ----------------------
# Data Cloud generates a KQ_ field on the DMO; it rides INLINE in the retrieved
# .object and the Metadata API rejects it ("Key Qualifier Field cannot be
# deployed using Data Kits", KB 005224006). Drop any <fields> block whose
# usageTag is KeyQualifier (or whose fullName starts with KQ_). Documented as a
# required manual step ("don't skip it") — automated here.
STRIPPED=0
if [[ -d "$MDROOT/objects" ]]; then
  for OBJ in "$MDROOT"/objects/*.object; do
    [[ -e "$OBJ" ]] || continue
    BEFORE=$(grep -c '<fields>' "$OBJ" || true)
    awk '
      /<fields>/ { infield=1; buf=$0 ORS; next }
      infield {
        buf = buf $0 ORS
        if ($0 ~ /<\/fields>/) {
          if (buf ~ /<usageTag>KeyQualifier<\/usageTag>/ || buf ~ /<fullName>KQ_/) {
            # drop this Key Qualifier field block
          } else {
            printf "%s", buf
          }
          infield=0; buf=""
        }
        next
      }
      { print }
    ' "$OBJ" > "$OBJ.tmp" && mv "$OBJ.tmp" "$OBJ"
    AFTER=$(grep -c '<fields>' "$OBJ" || true)
    STRIPPED=$(( STRIPPED + BEFORE - AFTER ))
  done
fi
echo "==> Stripped $STRIPPED Key Qualifier field block(s) from retrieved object(s)."

# --- 4. Deploy ----------------------------------------------------------------
echo "==> Deploying to $TARGET_ORG ${DRY_RUN:+(dry-run — no changes)}..."
set +e
DEPLOY_JSON=$(sf project deploy start --metadata-dir "$MDROOT" --target-org "$TARGET_ORG" \
  --ignore-conflicts --wait 30 $DRY_RUN --json 2>/dev/null)
DEPLOY_RC=$?
set -e

SUCCESS=$(jq -r '.result.success // false' <<<"$DEPLOY_JSON" 2>/dev/null || echo "false")
NUM_OK=$(jq -r '.result.numberComponentsDeployed // 0' <<<"$DEPLOY_JSON" 2>/dev/null || echo "0")
NUM_TOTAL=$(jq -r '.result.numberComponentsTotal // 0' <<<"$DEPLOY_JSON" 2>/dev/null || echo "0")

if [[ "$SUCCESS" != "true" || "$DEPLOY_RC" -ne 0 ]]; then
  echo "ERROR: deploy failed ($NUM_OK/$NUM_TOTAL components)." >&2
  echo "    Component failures:" >&2
  jq -r '.result.details.componentFailures[]? | "      \(.componentType) \(.fullName): \(.problem)"' <<<"$DEPLOY_JSON" >&2 2>/dev/null \
    || echo "      (no structured failures; re-run the sf command without --json to see detail)" >&2
  echo "    Hint: a missing 'FieldSrcTrgtRelationship' error means that type must be added to" >&2
  echo "    $WORKDIR/package.xml and the kit re-retrieved (see plan/30-promote.md §3)." >&2
  exit 1
fi

echo "==> Deploy ${DRY_RUN:+(dry-run) }succeeded: $NUM_OK/$NUM_TOTAL components."

# --- 5. Verify (real deploy only) --------------------------------------------
if [[ -z "$DRY_RUN" ]]; then
  echo "==> Verifying the kit is present in $TARGET_ORG ..."
  if sf org list metadata --metadata-type DataPackageKitDefinition --target-org "$TARGET_ORG" --json 2>/dev/null \
       | jq -e --arg k "$DATA_KIT" '.result[]? | select(.fullName == $k)' >/dev/null; then
    echo "    confirmed: DataPackageKitDefinition '$DATA_KIT' exists in $TARGET_ORG."
  else
    echo "    WARNING: could not confirm '$DATA_KIT' via metadata list — check the target manually." >&2
  fi
  cat <<EOF

==> Definition deployed. Data Cloud RUNTIME wiring is still manual in $TARGET_ORG (plan/30-promote.md §6):
      1. Activate the file (UploadedFiles) connection under Data Cloud Setup → Other Connectors.
      2. Re-authenticate / re-upload the CSV for the file connection.
      3. Activate the data stream so the DLO populates.
      4. Verify the DLO→DMO mapping and that the DMO previews data.
EOF
fi
