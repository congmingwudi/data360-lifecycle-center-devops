# References — Data 360 data kits, sandboxes, and deployment

A **reference** (not a numbered step). These are the official sources the runbook relies on for
moving a Data 360 (Data Cloud) data kit between orgs. Step docs link here when they cite one. Read
dates are recorded because these pages change.

| Source | Type | What it's authoritative for | Cited in |
|---|---|---|---|
| [Build and Share Data 360 Functionality](https://help.salesforce.com/s/articleView?id=data.c360_a_build_and_share_functionality.htm&type=5) | Salesforce Help (doc hub) | Top-level map of the ways to move or share Data 360 config: data kits, managed packages (AgentExchange), sandboxes, scratch orgs, external activation platforms. Links to *Packaging in Data Cloud*, *Data Kits*, and *Data 360 in a Sandbox*. | [`00-prereqs.md`](00-prereqs.md) |
| [Data 360 Sandboxes](https://trailhead.salesforce.com/content/learn/modules/data-360-sandboxes) | Trailhead module (4 units, ~30 min) | The end-to-end sandbox lifecycle: provisioning, refresh, DevOps kits, deployment tools, and pre- and post-deploy checklists. | [`00-prereqs.md`](00-prereqs.md); [`30-promote.md`](30-promote.md) §3d, §6|
| [Use CLI to Deploy Changes from Sandbox to Data 360](https://developer.salesforce.com/docs/data/data-cloud-dev/guide/dc-deploy_data_kit_using_cli.html) | Developer guide | The supported CLI path: Download Manifest, then `sf project retrieve start --manifest`, delete `KQ_*` files, then `sf project deploy start --manifest`. Also the `FieldSrcTrgtRelationship`, DLO schema, and inactive-connector fixes. | [`30-promote.md`](30-promote.md) §3d |
| [Use the Connect REST API to Deploy Data 360 Data Kits](https://developer.salesforce.com/docs/data/data-cloud-dev/guide/dc-deploy-data-kits-using-connect-api.html) | Developer guide (read 2026-10-26) | Deploying an *installed* kit's components (streams, DLOs, mappings): `POST /ssot/data-kits/{devName}?asyncMode=true` returns 202 with a `jobId`; poll `GET /ssot/datakit-deployment-job/{jobId}`. Common errors: an inactive connector, a duplicate API name in the data space, a data space mismatch. Verified differences are listed below. | [`30-promote.md`](30-promote.md) §6 step 3; [`scripts/deploy-datakit-components.sh`](../scripts/deploy-datakit-components.sh) |
| [Data 360 Connect API reference: Calculated Insights](https://developer.salesforce.com/docs/data/connectapi/references/spec?meta=createCalculatedInsight) | API reference (read 2026-10-27) | `POST /ssot/calculated-insights` with `apiName` (the `__cio` suffix is added), `displayName`, `definitionType` (`CALCULATED_METRIC`), `dataSpaceName`, `expression` (SQL), and `publishScheduleInterval` (`NotScheduled`, `One`, `Six`, `Twelve`, `TwentyFour`, …; a start time is required unless it's `NotScheduled`). Also `GET`/`PATCH`/`DELETE …/{apiName}` and `POST …/{apiName}/actions/run`. `actions/validate` returns `API_DISABLED_FOR_ORG` in `dcdev1`. | [`30-promote.md`](30-promote.md) §8; [`scripts/create-calculated-insight.sh`](../scripts/create-calculated-insight.sh) |
| [Data 360: Data Kit Considerations & Common Issues (KB 003960830)](https://help.salesforce.com/s/articleView?id=003960830&type=1) | Knowledge article (published 2026-09-02) | Data-kit limits and known failure modes, listed below. | [`30-promote.md`](30-promote.md) §6 |
| [Deploy Data 360 Changes Across Orgs](https://help.salesforce.com/s/articleView?id=data.c360_a_data_cloud_sandbox_deploy.htm&type=5) | Salesforce Help (read 2026-10-27) | The **change-set** path for DevOps kits. Step 4: *"When you deploy a data kit using a change set, the system automatically deploys the data kit and its components. If you deploy the same data kit by using another change set, the data kit installs but doesn't deploy the components. To complete the deployment, open your data kit, and click Deploy Data Kit."* | [DevOps vs. Standard](#devops-vs-standard-data-kits-compiled-2026-10-27); [`30-promote.md`](30-promote.md) §6 |
| [Considerations for Data Kits in Data 360](https://help.salesforce.com/s/articleView?id=data.c360_a_data_cloud_datakit_consideration.htm&type=5) | Salesforce Help (read 2026-10-27) | Per-component considerations. On connectors: *"DevOps Data Kit: When you deploy data streams using a DevOps data kit, Data 360 automatically adds the connector information to the target org."* Standard kits: build them *"from Developer Edition orgs only"*, and for non-DCF streams *"the connector details aren't included"*. Says nothing about automatic vs. manual component deploy. | [DevOps vs. Standard](#devops-vs-standard-data-kits-compiled-2026-10-27) |
| [Data Kits](https://help.salesforce.com/s/articleView?id=sf.c360_a_data_package_kits.htm&type=5) | Salesforce Help | Data kit concepts and the Standard vs. DevOps types. | Background only (not cited in a step) |

## DevOps vs. Standard data kits (compiled 2026-10-27)

**Use a DevOps kit for this pipeline.** The table shows why: you can build one in our `dcdev1`
sandbox, it moves through the Metadata API that Lifecycle Center uses, it carries its connector
information, and its Deploy call needs only the kit name. A Standard kit fails the first of these.

| | **DevOps kit** | **Standard kit** | Source |
|---|---|---|---|
| Purpose | Move config between your own orgs (dev → UAT → prod) | Distribute a solution in a managed package (AgentExchange) | Trailhead *Data 360 Sandboxes* |
| Where you can build it | Any org with Data Cloud, including a sandbox like `dcdev1` | **Developer Edition orgs only** | Considerations |
| How it moves | Change set, CLI manifest, or Metadata API (what Lifecycle Center uses) | Package install. A DevOps kit can't be packaged (our packaging finding) | Trailhead; CLI guide |
| Connector in the target | *"Data 360 automatically adds the connector information to the target org"*. Verified: staging's stream came bound to `UploadedFiles` | Pick a packaged or preconfigured connector at deploy time. For non-DCF streams *"the connector details aren't included"* | Considerations |
| The Deploy call (Connect API) | Kit name only. Verified: an empty `{}` body on v64.0 | Must list the components and their settings (`CdpDataKitDeployInputRepresentation`) | Connect API guide |
| Standard DMOs | Carried as configured | *"only the custom mappings and custom fields… are packaged"* | Considerations |
| Change set, sandbox → prod | **Required** | Not allowed | KB 003960830 |
| Data space | A space with the same name must already exist in the target (`default` here) | Chosen at deploy time | Change-set page; Connect API guide |
| Install vs. component deploy | **Separate steps** for a Metadata API install (CLI or Lifecycle Center). Verified below. A *first* change-set install deploys the components automatically; later ones don't | **Separate steps**: installing the package doesn't create the streams, so you deploy the kit afterwards | Change-set page; this project |
| Switching types later | Not possible on the same objects: *"can't be used interchangeably"*. A kit-deployed object can only be updated by redeploying **the same kit** | Same | KB 003960830 |

**What's verified here and what isn't.** The DevOps column's "Verified" cells come from `dcstaging1`
(2026-10-26) and were repeated in `afd360-prod` (2026-10-27). Nothing in the Standard column has been tested here; it all comes from the docs. The
install/deploy split for Metadata API installs was verified as follows:
- `branch_offices_datakit` was **first installed** at 21:33:29 UTC by the WI-000008 promotion
  (deploy `0AfDR00003eTycp0AC`).
- `DataKitDeploymentLog` (the Deployment History tab) had **no rows** for it until our Connect API
  job at 21:51:05.
- So the install never even *attempted* a component deploy. A failed attempt would have logged a
  row, as our accidental duplicate job did.
- **Confirmed in production (2026-10-27).** At 21:33 staging's UploadedFiles connection was still
  inactive, which left open whether an inactive connection had made the install skip the deploy.
  Production ruled that out. Its connection was already ACTIVE when the Lifecycle Center promotion
  installed the kit (deploy `0AfKa00000iyM8tKAE`, 13:18 UTC). The log still had no rows until our
  Connect API job `08PKa00000qP9r8` at 13:23 ([`30-promote.md`](30-promote.md) §5b).

## Key points relevant to this runbook (read 2026-10-12)

**From the Trailhead module *Data 360 Sandboxes*:**
- **Kit types:** **Standard** is for AgentExchange solution packages (partners). **DevOps** is for
  internal environment migration (dev → UAT → prod). This matches our packaging finding: a DevOps kit
  can't be packaged.
- **Deployment tools it lists for DevOps kits:** change sets, the **Salesforce CLI / Metadata API**
  (called the "gold standard"; store the manifest in Git), and **external DevOps tools** (Copado,
  Gearset, GitLab). **Lifecycle Center (DevOps Center) isn't mentioned.**
- **Key qualifier files:** *"Do not skip this step"*. Delete them before deploying. Our script and the
  `sf-d360-branches-datakit` repo do this.
- **CLI / source-control limitations it admits:** re-retrieving generates *new* XML file names, so
  `git diff`/`blame`/`merge` are ineffective. Template names collide (CI, CI1, CI2). Same-named kits
  from separate sandboxes don't merge, and neither does the publishing sequence.
- **Pre-deploy checks:** the data space must already exist in the target, and features must match.
  **To update an already-deployed component, create a *new* data kit.**
- **Post-deploy:** check **Data Kits → (kit) → Deployment History**. Deployed streams arrive in
  **draft/inactive**. For non-CRM connectors (like our File Upload), activate the connector, with no
  redeploy needed. CRM connectors need activation *and then a redeploy*. Then **Start Ingestion**.
- **Refresh:** back up sandbox Data 360 config with a DevOps kit *before* refreshing. A refresh
  overwrites the sandbox and copies metadata, not data.

**From KB 003960830 *Data Kit Considerations & Common Issues*:**
- Objects deployed by a kit can only be updated by **redeploying the same kit**. Standard and DevOps
  kits **can't be used interchangeably** on the same object. **Manually created objects can't be
  updated by any kit.**
- DLOs tied to a data stream can't be added on their own. Add the stream and the DLO comes with it.
- `FieldSrcTrgtRelationship` errors mean the DMO relationship must be added explicitly.
- **Sandbox → Production by change set requires a DevOps-type kit.** Object API names must be at
  most 40 characters.
- **A connection becomes inactive in the target when its data streams are deployed in a kit.** Not
  what we saw in `afd360-prod`. A connection that was already active there stayed ACTIVE and wasn't
  modified, so §6 step 2 is needed only where it's inactive. Data Transforms in a non-default data space can't be deployed
  through kits.
- Production → Production: non-default objects can't go into a data kit.

**From *Use the Connect REST API to Deploy Data 360 Data Kits* (read and tested 2026-10-26 in `dcstaging1`):**
- A kit must be **installed** (by a Metadata API deploy or a package) before its components can be
  deployed. Installing creates nothing that runs. This **component deploy** step is what creates the
  streams, DLOs, and mappings. It replaces the older `sfdatakit__DeployDataKitComponents` flow.
- What we saw differs from the guide in three ways:
  - The endpoint exists only from **v64.0**. v62.0 and v63.0 return `NOT_FOUND`, even though the
    guide's example uses v62.0.
  - v64.0 rejects the documented DevOps-kit body `{"developerName": "<kit>"}` with
    `JSON_PARSER_ERROR: Unrecognized field "developerName"`. An empty `{}` works.
  - The final status is `Complete`, not `Completed`.
- Two deploys of the same kit **running at once** fail with *"A data lake object with the name … already
  exists"*. A redeploy that starts after the first one finishes works. On 2026-10-27 it redeployed the
  stream bundle in place and added a new calculated insight ([`30-promote.md`](30-promote.md) §8).
  The deployment log names a calculated insight by its label.

**From *Build and Share Data 360 Functionality*:**
- Packaging means creating a data kit and adding it to a package. **Managed packages** are the route
  for distributing to customers on AgentExchange, while data kits handle deployment across orgs.
  Sandbox usage consumes production credits at discounted multiplier rates.
