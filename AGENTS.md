# Info

A system for modeling and applying defenses (minimizing blast radius) in computer networks.

SEE README.md FIRST

## General workflow

Your agent type: 
 - main agent if the prompt doesn't contain any info
 - subagent if prompt specifies it

Whenever you invoke/delegate to subagent always in prompt specify the subagent delegated to is a subagent.

General workflow is as follows:
 - always use `explorer_fast` model for exploring and review, never `Explorer`
 - use `implementor_fast` for implementation
 - when you are the main agent your responsibility is general thinking/approaching the problem and orchestrating subagents. For exploration and implementation use subagents as much as possible Pass context (including those from subagents) to subagents via temporary markdown files. You can do small fixes or quick pass reviews.
 - split plan (designed during planning mode) into reasonably small but logical chunks (e.g. BE chunk, FE chunk OR BE + FE chunk, vertical slice style). Handoff each chunk to implementation subagent along with relevant context
- do not write dry plan texts with plenty of bullets point and dry text. Add Diagrams IF relevant (that is flow visualization), code examples, architecture examples or diagrams if needed, interfaces in code, function signatures (conceptual), use cases, pseudocode, file tree layout, other. In general: use visualization tools that complements the plan in implementation hints AND example-oriented (for human).

## Infrastructure

Project uses Terraform for provisioning infrastructure - `/infra`.

Local environment module contains a helper script that supplies the fixed common
manifest. It does not load a local `.env` file. Use it for local Terraform:
`/infra/environments/local/terraform.sh`.

### Observability

Loki, Tempo and Promethesus are used for storing telemetry data.

### Secrets & inputs

To provide agnostic way of passing inputs and secrets, use two mechanisms: 

 - for non-sensitive inputs **environment variables**
 - for secrets **files** that have restrictive permissions or mounted into container

Good:
 - using .env for local development (gitignored!)
 - using secret managers (AWS, Hashicorp etc) to fetch state into files 
 - using sidecar or scripts that fetch vars right before starting the stack

Bad
 - hardcoding values passed in e.g. docker compose
 - "ifology" inside app (provider or SDK specific)

To discuss with user
 - "common defaults" like well-known service ports or port mappings (e.g. Grafana, PostgresSQL)

## Frontend

- Follow the conventions established in codebase
- For new components use bits-ui
- BE defined types contracts must match between frontend and backend (contracts/ directories)

## Documentation

- For interacting with user (this includes also your output regardless of mode) and/or writing documentation (in general) use `writing-clearly-and-concisely` skill.
- For writing *technical* documentation or acting as subagent (output) *always* use `asd-ste100` skill.
- Always use Mermaid for diagrams, including those embedded inside markdown blocks. See `mermaid-diagrams` for reference. Do not use ASCII art or other languages like PlantUML unless expliticly specified by the user
- Never copy paste source code or concrete values unless is for example purposes. It gets outdated very quickly. Instead point to relevant file/place for current values. The point is that documentation can get out of sync with aspects that change dynamically like source code
- Do not document what can be read from the config or source code. Document why, not what.
- Documentation files verbosity: Imagine you are lazy engineer who prefers doing useful work and hates absolutely documentation. Document absolute bare minimum, do not over explain. Brief sentences. If explanation is unclear, follow up with example (can be complex one) in elixir or pseudocode

## Agents

### Available

| Agent | File | Model | Purpose |
|-------|------|-------|---------|
| `explorer_fast` | `.opencode/agents/explorer_fast.md` | global | Fast codebase exploration, read-only |
| `svelte-file-editor` | `.opencode/agents/svelte-file-editor.md` | global | Svelte 5 component authoring with MCP docs |
| `visual-verifier` | `.opencode/agents/visual-verifier.md` | `commandcode/xiaomi/mimo-v2.5-pro` | Cheap UI verification via playwright-cli |

All agents use the single model set globally (CLI/config). `visual-verifier` is the only one with a per-agent model override.

Invoke subagents with `@name` (e.g. `@visual-verifier check the login page`).

## Post Completion Check of tasks

ALWAYS, THIS IS NOT NEGOTABLIE, POST CHECK your results. Fix? test it, query the db, check logs, check if the fix didn't broke anything else and actually worked.

## Project tracking

Repo issues: https://github.com/michalo1334/master_thesis/
