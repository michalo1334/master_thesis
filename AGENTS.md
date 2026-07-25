# Info

A system for modeling and applying defenses (minimizing blast radius) in computer networks.

SEE README.md FIRST

## Infrastructure

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

- Always activate `writing-clearly-and-concisely` skill before proceeding with writing documentation OR interacting with the user. UNCONDITIONALLY.
- Always use Mermaid for diagrams, including those embedded inside markdown blocks. See `mermaid-diagrams` for reference. Do not use ASCII art or other languages like PlantUML unless expliticly specified by the user
- Never copy paste source code or concrete values unless is for example purposes. It gets outdated very quickly. Instead point to relevant file/place for current values. The point is that documentation can get out of sync with aspects that change dynamically like source code
- Do not document what can be read from the config or source code. Document why, not what.
- Documentation files verbosity: Imagine you are lazy engineer who prefers doing useful work and hates absolutely documentation. Document absolute bare minimum, do not over explain. Brief sentences. If explanation is unclear, follow up with example (can be complex one) in elixir or pseudocode

## Agents

### Available

| Agent | File | Model | Purpose |
|-------|------|-------|---------|
| `explorer_fast` | `.opencode/agents/explorer_fast.md` | `opencode-go/deepseek-v4-flash` | Fast codebase exploration, read-only |
| `svelte-file-editor` | `.opencode/agents/svelte-file-editor.md` | `opencode-go/deepseek-v4-pro` | Svelte 5 component authoring with MCP docs |
| `visual-verifier` | `.opencode/agents/visual-verifier.md` | `opencode-go/minimax-m3` | Cheap UI verification via playwright-cli |

Invoke subagents with `@name` (e.g. `@visual-verifier check the login page`).

## Models

| Model ID | Used by | Purpose |
|----------|---------|---------|
| `opencode-go/deepseek-v4-flash` | `explorer_fast` | Fast, cheap codebase exploration |
| `opencode-go/deepseek-v4-pro` | `svelte-file-editor` | Heavier Svelte editing with doc lookups |
| `opencode-go/minimax-m3` | `visual-verifier` | Cheap browser-based visual checks |

## Post Completion Check of tasks

ALWAYS, THIS IS NOT NEGOTABLIE, POST CHECK your results. Fix? test it, query the db, check logs, check if the fix didn't broke anything else and actually worked.

## Project tracking

Repo issues: https://github.com/michalo1334/master_thesis/
