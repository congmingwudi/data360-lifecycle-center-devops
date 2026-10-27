# 40 — Optional: drive the pipeline with MCP tools / skills

Lifecycle Center exposes its operations to AI tooling two ways. Both automate the **Lifecycle Center** parts of the flow (create work item → commit → PR → promote). **Neither** automates the Data Cloud manual post-deploy steps in `30-promote.md §6` — plan to still do those by hand.

## Option A — Salesforce DX MCP Server (interactive, in an IDE)

- The **Salesforce DX MCP Server** exposes Lifecycle Center tools that an LLM can call to read/manage/operate Lifecycle Center resources.
- **Prereqs:** an MCP-enabled IDE (**Agentforce Vibes IDE** or VS Code) + the **Agentforce Vibes Extension**; host the DX MCP server; configure auth (approved org access).
- Good for interactive, live-data tasks: "show pipeline health", "what's the status of WI-000042", "resolve merge conflicts in WI-000042" (opens Agentforce Vibes), "analyze this deployment failure".
- Docs:
  - MCP tools & skills: https://help.salesforce.com/s/articleView?id=platform.devops_center_mcp_tools.htm&type=5
  - Tool descriptions: https://help.salesforce.com/s/articleView?id=platform.devops_center_mcp_tool_desc.htm&type=5
  - Work-item lifecycle via MCP: https://help.salesforce.com/s/articleView?id=platform.devops_center_mcp_work_item_management.htm&type=5

## Option B — sf-skills (headless, from the CLI)

- **Skills** are plain-text instruction packages that guide an AI tool through sequential **git + `sf` CLI** commands — **no server to host**, and they can run **headlessly** from the command line.
- Add the skill files to this repo; point your CLI-driven agent at them.
- Repo: **https://github.com/forcedotcom/sf-skills**
- Best fit for this experiment if you want the create→commit→PR→promote loop scripted and repeatable.

## Option C — plain Salesforce CLI

- You can **promote via `sf`** without any MCP layer at all.
- Quick start: https://help.salesforce.com/s/articleView?id=platform.devops_center_cli_quick_start.htm

## Recommendation

Do the **first** run through the **UI** (`10`→`20`→`30`) so you see each stage and the manual Data Cloud deltas plainly. Then, for a repeatable second run, layer in **Option B (sf-skills)** to script the Lifecycle Center lifecycle. Keep expectations honest: MCP/skills shorten the git+deploy loop, not the Data Cloud runtime wiring.

## Edition / availability note

MCP tools require Lightning Experience in Professional (API access), Enterprise, Performance, Unlimited, or Developer editions. **Not** available in Government Cloud Plus or the EU Operating Zone.

---

Next (optional/advanced): once you're driving the pipeline with an agentic surface, govern it → `50-cap-governance.md`.
