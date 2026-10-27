# plan/images/

Screenshots referenced by the `plan/` setup docs — visual "done when" evidence and UI
step callouts for performing this project's Lifecycle Center + Data Cloud setup.

Convention:
- **Name by the plan doc that uses it**: `<docnum>-<short-description>.png`
  (e.g. `00-lifecycle-center-home.png` is referenced by `plan/00-prereqs.md`).
- Reference from the doc with a relative link: `![alt](images/00-lifecycle-center-home.png)`.
- Capture the whole relevant panel, not a tight crop, so the surrounding nav gives context.

## Index

Names, usernames, org IDs, My Domain hosts and the GitHub repo are redacted (solid boxes) in
these screenshots. The customer deck ([`docs/index.html`](../../docs/index.html)) is built from the same
images.

| Image | Shows | Used by |
|-------|-------|---------|
| `00-lifecycle-center-home.png` | Lifecycle Center app home in the Hub org: Home / Projects / Pipelines / Work Items / Activity History tabs and the *Welcome to Lifecycle Center* banner. | `plan/00-prereqs.md` §1 |
| `00-lifecycle-center-setup.png` | **Setup → Lifecycle Center** (header still *DevOps Center*): *Enable Lifecycle Center* on, *DevOps Center Migration* and *Managed Package* off. | `plan/00-prereqs.md` §1 |
| `10-github-oauth-authorize.png` | GitHub "Authorize Salesforce DX" OAuth screen (the `alm2-dx-sfdc` app requesting your GitHub account, public + private repos). | `plan/10-lifecycle-center-setup.md` §2 |
| `10-github-connected.png` | Lifecycle Center home after connecting — "Connected as <your-github-user>" replaces the Connect card. | `plan/10-lifecycle-center-setup.md` §2 |
| `10-new-pipeline-connect-repo.png` | **New Pipeline** wizard step 1 — GitHub source control, "Connect to a repository", Repository URL. Shows the repo binds at the pipeline. | `plan/10-lifecycle-center-setup.md` §3a |
| `10-new-pipeline-connect-projects.png` | **New Pipeline** wizard step 2 — "Connect pipeline to projects", empty when building pipeline-first (link made from the project side instead). | `plan/10-lifecycle-center-setup.md` §3a |
| `10-pipeline-configure-stages.png` | Pipeline **Pipeline Stages** editor — Development Environments box + default Integration/UAT/Staging stages, repo bound, Activate greyed until setup done. | `plan/10-lifecycle-center-setup.md` §3b |
| `10-add-dev-environment.png` | **Add Environment** dialog — Environment Name `afd360-dcdev1`, Connect. | `plan/10-lifecycle-center-setup.md` §3b |
| `10-dev-environment-allow-access.png` | Salesforce **"Allow Access?"** OAuth consent for `ALMDevOpsConnectedApp` (dev sandbox user). | `plan/10-lifecycle-center-setup.md` §3b |
| `10-pipeline-staging-production-stages.png` | Pipeline trimmed to **Staging → Production** stages (Production branch `main`, Staging not yet connected). | `plan/10-lifecycle-center-setup.md` §3b |
| `10-connect-staging-environment.png` | **Add Environment** for the Staging stage — `afd360-dcstaging1`, **Sandbox**. | `plan/10-lifecycle-center-setup.md` §3b |
| `10-staging-connected.png` | Staging stage showing `afd360-dcstaging1` connected. | `plan/10-lifecycle-center-setup.md` §3b |
| `10-connect-production-environment.png` | **Add Environment** for the Production stage — `afd360-prod`, **Production Org**. | `plan/10-lifecycle-center-setup.md` §3b |
| `10-pipeline-stages-connected.png` | Final pipeline — `dcdev1` (Dev) → `dcstaging1` (Staging) → `afd360-prod` (Production/`main`); Release Environment `afd360-prod`. | `plan/10-lifecycle-center-setup.md` §3b |
| `10-specify-staging-branch.png` | **Add Branch** dialog for the Staging stage — "Create a branch from main", Branch Name `dcstaging1` (branched off `main`). | `plan/10-lifecycle-center-setup.md` §3b |
| `10-activate-pipeline-button.png` | Pipeline in **Ready** state — both branches assigned (Staging → `dcstaging1`, Production → `main`); the **Activate Pipeline** button (top-right) called out. | `plan/10-lifecycle-center-setup.md` §3b step 6 |
| `10-pipeline-activated.png` | Pipeline **after activation** — the stage editor has become the runtime **promotion board** (Approved Work Items → Staging `afd360-dcstaging1` → Production `afd360-prod`, greyed **Promote Stage**). Proof activation succeeded. | `plan/10-lifecycle-center-setup.md` §3b step 6 |
| `10-new-project-pipeline.png` | The **New Project** window filled in — Project Name `dc-data-kit-experiment`, a description, and Pipeline `dc-data-kit-experiment-pipeline` selected (no repo field). Repo binds at the pipeline, not the project. | `plan/10-lifecycle-center-setup.md` §4 |
| `10-project-created.png` | Project detail page for `dc-data-kit-experiment` — attached Pipeline, Release Environment `afd360-prod`, bound Repository, "Project Created" activity, Work Items (0). The §4 done-when evidence. | `plan/10-lifecycle-center-setup.md` §4 |
| `20-uploadedfiles-connector-active.png` | Data Cloud Setup → Connectors list — the **UploadedFiles** connection (type **File Upload**) showing **Active**. The sandbox activation prerequisite. | `plan/20-build-data-kit.md` §2 |
| `20-new-data-stream-file-upload.png` | **New Data Stream** source picker — **File Upload** selected under Other Sources. | `plan/20-build-data-kit.md` §2 |
| `20-data-stream-dlo-config.png` | DLO config step — Category **Other**, Primary Key **OfficeCode**, six supported fields from `branch-offices-seed.csv`. | `plan/20-build-data-kit.md` §2 |
| `20-data-stream-name-dataspace.png` | Final wizard step — Data Stream Name `branch-offices-seed.csv`, Data Space **default**, ready to Deploy. | `plan/20-build-data-kit.md` §2 |
| `20-data-stream-deployed.png` | Deployed stream detail — **Active**, 50 records processed, DLO `branch_offices_seedcsv__dll`, Data Mapping still **0/0**. §2 done-when. | `plan/20-build-data-kit.md` §2 |
| `20-map-new-custom-object.png` | Data Mapping → **Select Objects** → **Custom Data Model** tab → **New Custom Object** (not a standard party DMO). | `plan/20-build-data-kit.md` §3 |
| `20-custom-dmo-fields.png` | New Custom Object **Branch Office** (`Branch_Office`, Category Other) — field list with `OfficeCode` as Primary Key. | `plan/20-build-data-kit.md` §3 |
| `20-dlo-to-dmo-mapping.png` | Completed DLO→DMO field mapping — six source fields mapped to `Branch Office`, `OfficeCode` the key. | `plan/20-build-data-kit.md` §3 |
| `20-data-mapping-ready.png` | Stream Data Mapping panel reading **11/11 → READY** after mapping. §3 done-when. | `plan/20-build-data-kit.md` §3 |
| `20-data-explorer-preview.png` | **Data Explorer** previewing the `Branch Office` DMO rows in the `default` data space (source `UploadedFiles`). §3 done-when. | `plan/20-build-data-kit.md` §3 |
| `20-new-data-kit-devops.png` | **New Data Kit** dialog — **Data Kit Type DevOps**, Data Space **default**, name `branch offices datakit`. | `plan/20-build-data-kit.md` §4 |
| `20-data-kit-created-empty.png` | Freshly created kit — empty contents, red **"Publishing sequence not defined"**. | `plan/20-build-data-kit.md` §4 |
| `20-kit-add-stream-bundle.png` | **Add Data Stream Bundles** — Connector Type File Upload, bundle `branch_offices_bundle`, `branch-offices-seed.csv` selected. | `plan/20-build-data-kit.md` §4 |
| `20-kit-add-related-objects.png` | Related objects — **UploadedFiles** connection + **Branch Office** data model; connector-metadata warning (re-wire in target). | `plan/20-build-data-kit.md` §4 |
| `20-kit-policies-none.png` | Wizard **Policy Rule Definitions** step — none applied. | `plan/20-build-data-kit.md` §4 |
| `20-kit-tags-none.png` | Wizard **Tags** step — none; Save. | `plan/20-build-data-kit.md` §4 |
| `20-data-kit-contents.png` | Populated **Data Kit Contents** — Data Stream Bundles (1) `branch_offices_bundle`, Data Models (1) `Branch Office` (`Branch_Office__dlm`). | `plan/20-build-data-kit.md` §4 |
| `20-data-kit-connections.png` | Kit **Connections (1)** — `UploadedFiles` (type UploadedFiles, method Source). | `plan/20-build-data-kit.md` §4 |
| `20-data-kit-publishing-sequence.png` | **Publishing Sequence** tab — Edit Sequence; order 1 `UploadedFiles` (Connection), 2 `branch_offices_bundle` (Data Stream Bundle). | `plan/20-build-data-kit.md` §4 |
| `30-new-work-item.png` | **New Work Item** dialog — Project `dc-data-kit-experiment`, Subject `WI — branch offices data kit`, Assignee, Development Environment `afd360-dcdev1`. | `plan/30-promote.md` §1 |
| `30-work-item-new.png` | Work item **WI-000001** at status **New** — status tracker, empty **Branch**, **Mark as in Progress** button. | `plan/30-promote.md` §1 |
| `30-work-item-in-progress.png` | Work item **In Progress** — green "status updated successfully" toast, tracker advanced, **Branch** now `<repo>/WI-000001` (verified: no `feature/` prefix). | `plan/30-promote.md` §2 |
| `30-dx-inspector-launch.png` | Launching **DX Inspector** from the hamburger menu in `dcdev1` (Data Cloud). | `plan/30-promote.md` §3a |
| `30-dx-inspector-signin-devops.png` | DX Inspector **Change Management** before connecting — "Sign in to DevOps Center" banner over the full (unfiltered, 156-item) change list. | `plan/30-promote.md` §3a |
| `30-dx-inspector-devops-oauth.png` | **Confirm External Access** OAuth consent linking DX Inspector to the Lifecycle Center Hub. | `plan/30-promote.md` §3a |
| `30-dx-inspector-connected.png` | DX Inspector header reading **"Connected to ALM Devops Center Hub"** — commits can now attach to a work item. | `plan/30-promote.md` §3a |
| `30-dx-inspector-select-components.png` | Change list on the **`branch`** filter pass (of two — the other filters `upload`), **select-all**, 60 data-kit components selected (`DataPackageKitDefinition`, `DataKitObjectDependency`/`Template`, `DataStreamTemplate`, `DataSrcDataModelFieldMap`). | `plan/30-promote.md` §3b |
| `30-dx-inspector-upload-filter.png` | The second (**`upload`**) filter pass — surfaces the `UploadedFiles*` connector pieces (`UploadedFiles1` → `DataKitObjectDependency`, `UploadedFiles` → `DataKitObjectTemplate`) and the `branch_offices_datakitUploaded*` field maps; the 60-selected count carries across both views. | `plan/30-promote.md` §3b |
| `30-commit-select-work-item.png` | **Commit Files** wizard step 1 — select work item **WI-000001** (`IN_PROGRESS`) under project `dc-data-kit-experiment`. | `plan/30-promote.md` §3c |
| `30-commit-preview.png` | **Commit Files** Preview — comment "Add branch offices data kit", Source Control Branch `…/tree/WI-000001`, component list, and the **Commit** button (the actual commit action). | `plan/30-promote.md` §3c |
| `30-dx-inspector-commit-failed.png` | Commit Completed activity-log detail: **Error**, *"We couldn't commit your changes…"*, the DX Inspector data-kit commit failure. | Customer deck |
| `30-promote-stage-cant-validate.png` | **Can't validate promotion**: *"…your source control is checking the pull request. Try again later."* A temporary state; retrying worked. | `plan/30-promote.md` §5b |
| `30-promotion-options.png` | **Promotion Options** for Staging → Production: Promote Now, only changes missing from Production, no tests. | `plan/30-promote.md` §5b |
| `30-production-promoted.png` | Pipeline after Promote Stage: Staging empty, Production *Latest Promotions* lists WI-000007 and WI-000008 together. | `plan/30-promote.md` §5b |
| `30-stream-update-file.png` | The kit-deployed stream `branch_offices_seedcsv` in `dcstaging1` after the component deploy: **Inactive**, 0 records, *Fields mapped 10/11*, and the **Update File** button. | `plan/30-promote.md` §6 step 4 |
| `30-stream-list-update-file.png` | Data Streams list in `afd360-prod`: the kit-deployed `branch_offices_seedcsv` (File Upload, Inactive), with the row menu open on **Update File**. | `plan/30-promote.md` §6 step 4 |
| `30-prod-stream-active.png` | `branch_offices_seedcsv` in `afd360-prod` after the upload: **Success**, **Active**, 50 processed, 50 total records. | `plan/30-promote.md` §5b |
| `30-stream-upload-file-dialog.png` | **Update Data Stream from a File**: Full Refresh selected, `branch-offices-seed.csv` uploaded (*File Upload Complete*), then **Deploy**. | `plan/30-promote.md` §6 step 4 |
| `30-ci-created.png` | *Branch Footprint by Region* calculated insight in `dcdev1`: Active, `default` space, last run Success. | `plan/30-promote.md` §8 step 1 |
| `30-kit-add-calculated-insight.png` | The data kit's **Add Calculated Insights** dialog with *Branch Footprint by Region* selected. | `plan/30-promote.md` §8 step 2 |
| `30-wi9-change-list.png` | WI-000009 Change List after the scripted commit: 3 changed components (kit object NEW, CI template NEW, kit definition CHANGE). | `plan/30-promote.md` §8 step 3 |
| `30-wi9-activity-history.png` | WI-000009 Activity History: Commit Started → 3× Commit Component → Commit Completed, all SUCCESS. | `plan/30-promote.md` §8 step 3 |
| `30-wi9-in-progress.png` | WI-000009 moved to In Progress: Lifecycle Center created branch `WI-000009` (the commit script's target). | `plan/30-promote.md` §8 step 3 |
| `30-wi9-review-created.png` | DX Inspector in `dcdev1` after **Create Review**: "Review for WI-000009 was created" (opens the PR to `dcstaging1`). | `plan/30-promote.md` §4 |
| `30-wi9-in-review.png` | WI-000009 In Review: "View and approve the pull request" plus **Mark as Ready to Promote**. | `plan/30-promote.md` §4 |
| `30-wi9-ready-to-promote.png` | WI-000009 Ready to Promote ("Approved by … View Pipeline"). | `plan/30-promote.md` §4 |
| `30-staging-approved-wi9.png` | Pipeline: WI-000009 in Approved Work Items, ready for **Promote Selected** to Staging. | `plan/30-promote.md` §8 step 4 |
| `30-staging-promotion-options.png` | Promote Selected options for Staging: only changes missing from Staging, no tests. | `plan/30-promote.md` §8 step 4 |
| `30-staging-wi9-promoted.png` | Promotion Successful: WI-000009 now in the Staging column, Promote Stage enabled. | `plan/30-promote.md` §8 step 4 |
| `30-staging-ci-run-now.png` | *Branch Footprint by Region* in `dcstaging1` after the component deploy: Active, never run, ▾ menu open on **Run Now**. | `plan/30-promote.md` §8 step 4 |
| `30-staging-ci-query.png` | Query Editor in `dcstaging1`: `SELECT … FROM branch_footprint_by_region__cio`, 24 rows (region × country). | `plan/30-promote.md` §8 step 4 |
| `30-prod-promote-stage-wi9.png` | Pipeline before Promote Stage: WI-000009 in Staging; Production lists WI-000007/8. | `plan/30-promote.md` §8 step 5 |
| `30-prod-promotion-options.png` | Promote Stage options for Production: Promote Now, only changes missing from Production, no tests. | `plan/30-promote.md` §8 step 5 |
| `30-prod-wi9-promoted.png` | Promotion Successful: WI-000009 in Production's Latest Promotions (7:29 AM). | `plan/30-promote.md` §8 step 5 |
| `30-prod-ci-run-now.png` | Calculated Insights list in `afd360-prod`: *Branch Footprint by Region* Active, created 7:33 AM by the kit deploy, never run; ▾ → Run Now. | `plan/30-promote.md` §8 step 5 |
| `30-prod-ci-query.png` | Query Editor in `afd360-prod`: `SELECT … FROM branch_footprint_by_region__cio`, 24 rows. | `plan/30-promote.md` §8 step 5 |
