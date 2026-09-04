# Common Implementation Instructions

- Act as a subagent. Use the repository instructions in `AGENTS.md` and `src/AGENTS.md`.
- Load and follow the `asd-ste100` skill for technical output.
- Load and follow the `ponytail` skill. Make the smallest correct change.
- Read the referenced design and execution files before editing.
- Preserve unrelated worktree changes. Do not revert or rewrite them.
- Use `apply_patch` for manual edits.
- Keep telemetry metadata bounded. Never add partition keys to metric metadata.
- Preserve original exception stacktraces.
- Do not add dependencies, processes, configuration, migrations, or compatibility layers.
- Do not implement work assigned to Phase 2.
- Do not run build, test, lint, format, git, or other verbose commands. The main agent delegates those commands separately.
- Report changed files, important decisions, and any unresolved risk.
