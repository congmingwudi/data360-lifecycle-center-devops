# scripts/

Reusable automation for setting up this Lifecycle Center data-kit pipeline in **any**
environment. Convention for this project: **every automated setup step we perform gets a
script here** — so the same action can be replayed against a different org (a fresh Hub,
another sandbox pair, a colleague's estate) without re-deriving the commands.

Principles:
- **Parameterize the target org** (`--target-org <alias|username>`), never hard-code it.
- **Idempotent + verifying** — safe to re-run; each script confirms its own result and exits
  non-zero on failure.
- **CLI-automatable steps only.** UI-only steps (T&C acceptance, Data Cloud "Get Started",
  data-space creation) stay in `plan/` as manual instructions; scripts note where they hand off.

## Scripts

| Script | What it does | Plan step |
|--------|--------------|-----------|
| `setup-devops-center-hub.sh` | Assigns the 3 Lifecycle Center permission sets to a Hub org's running user and verifies. | `plan/00-prereqs.md` §2 |
| `verify-datacloud-prereqs.sh` | Read-only: confirms Data Cloud is provisioned and the pipeline's data space is ACTIVE, in each env. | `plan/00-prereqs.md` §4–§5 |
| `watch-datakit-deploy.sh` | Observe **how** the kit deploys (Metadata API vs. `sfdatakit__DeployDataKitComponents` flow): `--status` pre-flight, `--arm` a debug-log trace flag before promoting, `--collect` the evidence after. `-u/--user` (the stage's Lifecycle Center OAuth user) is required. Read-only except `--arm`. | `plan/30-promote.md` §5a |
| `cancel-work-item.sh` | Cancels a work item (sets Status `NEVERED`, the "Never Mind" action) so you can abandon one stuck with a failed/stalled commit and start fresh. Idempotent; the UI offers no delete and a hard delete would orphan the branch. | `plan/30-promote.md` §3 |
| `deploy-datakit-cli.sh` | Deploys a Data Cloud data kit source→target via the **supported CLI manifest path** (fetch manifest → build package.xml → retrieve → strip the `KQ_*` Key Qualifier field → deploy; `--dry-run` to validate only). Direct, outside-the-pipeline path (the Salesforce-documented CLI route), for when you don't want Lifecycle Center in the loop: Lifecycle Center's commit **cannot** carry data-kit metadata, and for the pipeline the recommended route is `commit-datakit-to-work-item.sh`. Only the definition moves; run `deploy-datakit-components.sh` afterwards for the streams, DLOs and mappings, then do the remaining §6 steps by hand. | `plan/30-promote.md` §3 |
| `commit-datakit-to-work-item.sh` | **Recommended way to commit a data kit** (use it instead of DX Inspector; it also works around the failed DX Inspector commit). It retrieves exactly the kit's manifest members (source format) from the dev org into an isolated worktree of the work item's `WI-*` branch, strips `KQ_*`, raises `sourceApiVersion`, optionally check-only deploys to the next stage (`--validate-org`), commits as you (`--author` to override) and pushes fast-forward only. It then waits for Lifecycle Center to inspect the push and checks that the work item's Change List matches the kit members the commit changed. `--record-commit` is a fallback that writes the SHA onto the work item's `WorkItemComponentList` if no inspection appears. The work item is then promoted in the Lifecycle Center UI. Only one run per work item at a time: a lock stops a second, concurrent run, because both would share the worktree. | `plan/30-promote.md` §3e |
| `deploy-datakit-components.sh` | **Run after every install of a kit** (promotion or `deploy-datakit-cli.sh`). Installing brings only the kit definition and templates. This script runs the kit's **Deploy** action through the Connect API (`POST /ssot/data-kits/<kit>?asyncMode=true`, then polls the job). That creates the data streams, DLOs, and DLO→DMO mappings in the target. Its pre-flight prints the kit's deployment log (`DataKitDeploymentLog`, the Deployment History tab), so you can see whether anything has already tried to deploy it in that target. It compares the kit's publishing sequence with that log and with the org, and deploys only if some item was never deployed (for example a calculated insight added to the kit later). After the job it shows that job's log and checks that each of those items deployed, then prints a single `RESULT: SUCCESS`/`FAILED` line. A redeploy replays the whole sequence. Already-deployed items redeploy in place (verified 2026-10-27). Two deploys running at once fail on the duplicate DLO. First make sure the connection is active: it was inactive in `dcstaging1` but already active in `afd360-prod`. The streams arrive INACTIVE. | `plan/30-promote.md` §6 step 3 |
| `create-calculated-insight.sh` | Creates the *Branch Footprint by Region* calculated insight (`branch_footprint_by_region__cio`: offices per region and country from `Branch_Office__dlm`) through the Connect API (`POST /ssot/calculated-insights`). With `--run` it also runs it once and prints its rows (total should be 50). It skips if the insight exists. `--sql-file` overrides the SQL. Adding it to the kit stays a UI step. **In a target org use `--run-only`**: it runs the insight the kit deployed and prints its rows, but never creates one. It fails if the insight is missing (for example before `deploy-datakit-components.sh`), because an insight created by hand isn't owned by the kit and no kit can update it later. | `plan/30-promote.md` §8 |

## Usage

```bash
scripts/setup-devops-center-hub.sh --target-org afd360-prod
scripts/verify-datacloud-prereqs.sh -o afd360-dcdev1 -o afd360-dcstaging1

# Watch how a promotion deploys the kit (run against the TARGET org):
scripts/watch-datakit-deploy.sh -o afd360-dcstaging1 -u someone@example.com            # pre-flight status
scripts/watch-datakit-deploy.sh -o afd360-dcstaging1 -u someone@example.com --arm      # before promoting
scripts/watch-datakit-deploy.sh -o afd360-dcstaging1 -u someone@example.com --collect  # after promoting

# Abandon a stuck work item (Hub org), then create a fresh one to continue:
scripts/cancel-work-item.sh --target-org afd360-prod --work-item WI-000001

# Recommended: commit the kit to a new work item's WI-* branch (WI-00000N, In Progress), then promote in the Lifecycle Center UI:
scripts/commit-datakit-to-work-item.sh -k branch_offices_datakit -s afd360-dcdev1 \
    --hub afd360-prod -w WI-00000N --validate-org afd360-dcstaging1 --dry-run

# Direct non-pipeline alternative: deploy via the CLI manifest path (validate first):
scripts/deploy-datakit-cli.sh -k branch_offices_datakit -s afd360-dcdev1 -o afd360-dcstaging1 --dry-run
scripts/deploy-datakit-cli.sh -k branch_offices_datakit -s afd360-dcdev1 -o afd360-dcstaging1   # real deploy

# After the kit is installed in a target, create its streams/DLOs/mappings (activate the connection first):
scripts/deploy-datakit-components.sh -k branch_offices_datakit -o afd360-dcstaging1 --dry-run
scripts/deploy-datakit-components.sh -k branch_offices_datakit -o afd360-dcstaging1

# Update-only test: create the calculated insight in dev1 (then add it to the kit in the UI):
scripts/create-calculated-insight.sh -o afd360-dcdev1 --dry-run
scripts/create-calculated-insight.sh -o afd360-dcdev1 --run
scripts/create-calculated-insight.sh -o afd360-prod --run-only   # target: after the component deploy, run the kit's insight
```

Requires the `sf` CLI (authenticated to the target org) and `jq`; `commit-datakit-to-work-item.sh`
also needs `git` with push access to `origin`.
