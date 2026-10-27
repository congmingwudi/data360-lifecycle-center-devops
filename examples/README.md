# examples/

Reference metadata only. Nothing here is part of the pipeline: the root `sfdx-project.json` lists
only `force-app/` as a package directory, so Lifecycle Center never inspects or deploys this folder.

## `branch_offices_datakit/`

The source of the test data kit, `branch_offices_datakit`, as it landed on the Production branch
(`main`) after promotion. [`scripts/commit-datakit-to-work-item.sh`](../scripts/commit-datakit-to-work-item.sh)
wrote it to the work-item branches, from the kit's own manifest. It's the config built by hand in
[`plan/20-build-data-kit.md`](../plan/20-build-data-kit.md), plus the calculated insight added in
[`plan/30-promote.md`](../plan/30-promote.md) §8:

| Folder | What it is |
|---|---|
| `dataPackageKitDefinitions/` | The DevOps-type kit itself, in the `default` data space |
| `DataPackageKitObjects/` | The kit's publishing sequence: connection, stream bundle, DMO, calculated insight |
| `mktDataSources/`, `dataKitObjectTemplates/`, `dataKitObjectDependencies/` | The `UploadedFiles` (File Upload) connection template |
| `dataSourceBundleDefinitions/`, `dataSourceObjects/`, `dataStreamTemplates/` | The `branch_offices_bundle` stream bundle and the `branch-offices-seed.csv` stream template |
| `objects/Branch_Office__dlm/` | The custom DMO and its fields, with the `KQ_*` Key Qualifier field removed (it won't deploy) |
| `dataSrcDataModelFieldMaps/` | The nine DLO → DMO field mappings |
| `dataCalcInsightTemplates/` | The *Branch Footprint by Region* calculated insight |

What to use it for:

- **Check your own commit.** After the commit script runs against your dev sandbox, its `WI-*`
  branch should hold the same metadata types. The file names will differ, because Data Cloud mints
  new numeric suffixes on every retrieve.
- **Read the shape of a kit** before you build one: which pieces are templates, and what actually
  creates the stream, DLO and mapping in a target (the component deploy, not the install; see
  [`plan/30-promote.md`](../plan/30-promote.md) §6).

The user ID in the connection template's `createdBy`/`lastModifiedBy` and in the stream template's
`importDirectory` has been replaced with the placeholder `005000000000000AAA`. The values are
informational, and they're specific to the org the kit was built in.

**The tested path builds the kit in the dev sandbox UI** ([`plan/20`](../plan/20-build-data-kit.md))
and moves it with the commit script and Lifecycle Center. Deploying this folder straight to an org
(`cd examples/branch_offices_datakit && sf project deploy start --source-dir force-app --target-org <alias>`)
is the same kind of Metadata API deploy as the direct CLI path in [`plan/30-promote.md`](../plan/30-promote.md) §3d,
but it wasn't tested from this folder. If you try it, the target needs Data Cloud and the `default`
data space, and you still run [`scripts/deploy-datakit-components.sh`](../scripts/deploy-datakit-components.sh)
afterwards to create the stream, DLO and mappings.
