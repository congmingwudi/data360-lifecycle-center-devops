# 50 — Optional (advanced): CAP Governance on the pipeline

> **Orgs:** the `afd360-*` aliases used here are defined in [`orgs.md`](orgs.md).

**Do this last.** Only after you've completed at least one clean manual run through
`10`→`20`→`30` (and ideally scripted a second run per `40`). CAP Governance governs
**AI coding agents**, not the manual Lifecycle Center flow — so it adds nothing until you start
driving the pipeline with agentic tooling.

## What CAP Governance is

- **CAP = Coding Agent Platform** — the Salesforce platform behind its AI coding-agent surfaces
  (Agentforce Vibes, Codey Studio, Builder Central, and Lifecycle Center's own "Agentic ALM" agents).
- **CAP Governance (CAP-G)** is a **policy-enforcement engine that constrains what those AI agents
  are allowed to generate and do.** It enforces deterministic guardrails — e.g.:
  - block **direct deployments to production orgs** (agent hard-refuses and cites the policy),
  - enforce **naming conventions** (e.g. object/API-name prefixes),
  - **block specified metadata types** (e.g. Apex, certain config),
  - require **pre-deploy lint / source validation**.
- The direction of travel: Lifecycle Center (renamed from DevOps Center in Winter '27) becomes the **central
  place you author governance policies**, and the AI agent surfaces download and enforce them.

> **Verification caveat (read before relying on this):** the exact setup toggle wording
> ("Enable CAP Governance"), its precise runtime behavior in the pipeline, and whether it's
> reversible were **not confirmable** from public Salesforce Help/Trailhead at the time this doc
> was written — this is a very new setting tied to the DevOps Center → Lifecycle Center + CAP-G
> merger. **Read the in-product hover/help text next to the toggle in `afd360-prod` before enabling**,
> and treat this doc as a starting map, not gospel.

## Why it was OFF for the manual experiment

The `10`→`30` runbook is driven by **manual Lifecycle Center work-item promotion** — no AI coding
agent is generating or deploying anything. CAP-G only intercepts **agentic** actions, so enabling
it earlier would have governed nothing while adding a moving part. It becomes relevant exactly when
you adopt `40`'s agentic paths (DX MCP Server / sf-skills / Agentforce Vibes).

## Prerequisites (confirm before enabling)

1. **Org release/patch level** — early CAP-G supported **sandbox orgs only**; production enforcement
   required a later patch (~262.14). Confirm `afd360-prod` is current enough to fetch/enforce
   policies from a production hub. **Done when:** you can locate the CAP Governance setting in
   Lifecycle Center setup without an "unavailable/upgrade" notice.
2. **Not for GovCloud / air-gapped** — CAP is hosted outside Hyperforce; it does not work in
   Government Cloud or air-gapped environments. (Not a constraint for this demo estate, but note it.)
3. **You are actually using an agentic surface** — there's nothing to govern until an agent
   (Codey Studio / Agentforce Vibes / DX MCP) is driving changes against `afd360-dcdev1`.

## Suggested sequence (once prereqs hold)

1. **Author one narrow policy first.** Start with a single, obviously-safe rule so you can watch it
   fire — e.g. *block direct deploys to production* or a naming-prefix rule on new objects. Note: metadata
   reaches `afd360-prod` only via Promote Stage, but `scripts/deploy-datakit-components.sh` and
   `scripts/create-calculated-insight.sh --run-only` act directly on prod after each promotion
   (`30-promote.md §6`), so a production-deploy block would also stop them. Start with the
   naming-prefix rule, or exempt those scripts.
2. **Enable CAP Governance** in the Lifecycle Center setup (read the hover text).
3. **Trigger an agentic action** that violates the policy (e.g. ask the agent to deploy to prod)
   and confirm the **hard refusal** — the agent should quote the blocking policy and redirect you
   to the pipeline.
   - **Done when:** you've observed one policy enforce (refusal + cited policy id) on an agent action
     in `afd360-dcdev1`, and a compliant action still succeeds.
4. **Record the finding** — same spirit as `30-promote.md §7`: note *what CAP-G blocked, what it let
   through, and whether the guardrail helped or just got in the way* for a data-kit workflow.

## What this is NOT

- It is **not** a promotion-approval / change-approval gate on your manual work items (that was my
  first wrong guess at the acronym). It governs **AI agents**, not human-driven promotions.
- It does **not** replace the manual Data Cloud post-deploy steps in `30-promote.md §6` — CAP-G has
  no bearing on confirming the data space, activating the UploadedFiles connection, running the
  component deploy, or the Update File upload that activates the stream.

---

This is the end of the runbook. If CAP-G turns out irrelevant to a pure data-kit workflow, that
itself is a finding worth writing down.
