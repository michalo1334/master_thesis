# pi-fusion local fork

This extension implements a lead/sidekick harness for Pi. The lead owns requirements, decisions, review, and commits.
The sidekick implements and checks delegated work.

This is a local fork of [`JoniBR/pi-fusion`](https://github.com/JoniBR/pi-fusion), fixed for Pi 0.87.1. See
`PROVENANCE.md` for the imported commit and license declaration.

## Tools

- `delegate(brief)` starts a sidekick with a new context. It returns a report and a `task_id`.
- `follow_up(task_id, message)` continues that sidekick context. A task ID works only while the same Pi process runs. Pi
  saves the sidekick session file. You can inspect it with `pi --resume` after a restart, but `follow_up` cannot reopen
  it.

## Lead skill

The lead can load the `fusion` delegation playbook from `.pi/skills/fusion/SKILL.md`. The sidekick does not load it.

## Sidekick environment

The sidekick reads project context files, including `AGENTS.md`. It does not load skills, prompt templates, or themes.
It does not load arbitrary project extensions. It cannot call `delegate` or `follow_up`, so it cannot create or continue
nested sidekicks. Configuration that requests those tools or the Fusion extension fails before the sidekick starts.

`fusion.sidekickTools` is an exact tool allowlist. The supported values are:

- Pi built-ins: `read`, `bash`, `edit`, `write`, `grep`, `find`, and `ls`.
- MCP adapter tools: `mcp`, `mcpScript`, `mcp__blender_mcp`, `mcp__svelte`, and `mcp__web_search`.

`fusion.sidekickExtensions` selects the package extensions that the sidekick loads. The supported values are
`pi-mcp-adapter` and `context-mode`. Select `pi-mcp-adapter` when `sidekickTools` contains an MCP adapter tool.

In Pi 0.87.1, `context-mode` registers commands and hooks, not callable `ctx_*` tools. It can run in the sidekick, but
it does not add a callable tool name.

A policy change applies to a new `delegate` call. A `follow_up` call keeps the existing sidekick session and tool set.

## Configuration

Set the sidekick model, timeout, tools, and extensions in `.pi/settings.json` or the user-level Pi settings:

```json
{
  "fusion": {
    "sidekickModel": "provider/model[:thinking]",
    "timeoutMinutes": 10,
    "sidekickTools": ["read", "bash", "edit", "write", "grep", "find", "ls"],
    "sidekickExtensions": []
  }
}
```

Run `/fusion-model` without an argument to select a provider and model in the Pi TUI. Use
`/fusion-model provider/model[:thinking]` to set a value directly. `PI_FUSION_MODEL` overrides settings. The slash
command overrides both.
