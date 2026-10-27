# Orgs — reference

The plan docs refer to three Salesforce orgs by their **`sf` CLI alias**. This is the one place
those aliases are defined; every other `plan/` doc links here instead of redefining them. The
machine-readable twin of this table is [`config/environments.json`](../config/environments.json)
(where `alias` is authoritative — usernames/hosts need not match it).

> **These aliases are the only estate-specific names in the runbook.** Usernames, My Domain hosts
> and the GitHub repo are shown as placeholders (`<your-username>`, `<your-github-org>`, …).
> Everything else we mint (the Lifecycle Center project `dc-data-kit-experiment`, the data kit
> `branch offices datakit`) is deliberately generic. To run this against your own orgs, either
> log in to them under these same aliases (`sf org login web --alias afd360-dcdev1 …`) or
> re-point the aliases in the commands — the rest carries over unchanged.

| Alias | Short | Role | Pipeline stage | Type | Notes |
|-------|-------|------|----------------|------|-------|
| `afd360-prod` | `prod` | Lifecycle Center **Hub** + **Production** release target | Production → `main` branch | Production | Durable home org. Work items + pipeline definition live here **and** it is the final promotion stage. A sandbox refresh would wipe Lifecycle Center + Data Cloud state, so this must not be a sandbox. Promoting a data kit to Production deploys it here; Data Cloud is already provisioned in this org (it's the parent prerequisite for Data Cloud in the sandboxes). |
| `afd360-dcdev1` | `dcdev1` | **Development** | Development (no stage branch) | Sandbox | Where the file-upload data stream → DLO → DMO → data kit is built; Lifecycle Center tracks the changes here to commit via a work item. |
| `afd360-dcstaging1` | `dcstaging1` | **Staging** (mid promotion stage) | Staging → `dcstaging1` branch (intermediate, cut from `main`) | Sandbox | Promotion target between Dev and Production. Uses the `default` data space, which already exists (nothing to pre-create). The UploadedFiles connection arrived inactive here and had to be activated. After each install, run `scripts/deploy-datakit-components.sh` and, the first time, Update File. |

**Pipeline shape:** `afd360-dcdev1` (Development) → `afd360-dcstaging1` (Staging) → `afd360-prod`
(Production). Branch mapping is right-to-left, so the **last stage (Production) owns `main`** and
Staging maps to an intermediate branch (`dcstaging1`, cut from `main`) — not `main` itself.

Where a doc writes just `dcdev1` / `dcstaging1` (the short name), it means the same sandbox as the
full `afd360-` alias above — the short form is used in running prose, the full alias in `sf` commands
and OAuth connect steps.
