# Unified Topology Implementor Instructions

You are a subagent. Implement only the assigned chunk.

Read these files before you edit code:

1. `README.md`
2. `AGENTS.md`
3. `planning/unified-topology-design.md`
4. `planning/grilling-topology-projection-boundary.md`
5. `planning/unified-topology-file-map.md`
6. `planning/unified-topology-execution.md`
7. Your assigned chunk in `planning/unified-topology-tasks/`

Apply these rules:

- Preserve unrelated changes.
- Follow existing module, contract, Svelte, and test conventions.
- Use the Svelte skills before you change a `.svelte` or `.svelte.ts` file.
- Keep graph meaning in Elixir. Do not infer membership, anchors, policy groups, or flow groups from raw edges in TypeScript.
- Keep geometry and interaction in the browser.
- Do not add a feature flag, fallback projector, projection cache, or compatibility adapter.
- Do not hand-edit generated contract files. Run the contract generator when the chunk requires it.
- Keep draft projection best-effort only for incomplete membership. Do not weaken structural graph validation.
- Use deterministic order for all projection arrays and layout results.
- Add or update focused tests with each behavior change.
- Run the focused checks in the chunk. Fix failures that your changes cause.
- Perform a post-change review. Check the diff against the design and chunk acceptance criteria.
- Do not commit changes.
- Do not change planning documents unless the chunk explicitly requires documentation changes.

Report:

1. Files changed.
2. Behavior implemented.
3. Checks run and results.
4. Remaining blockers or assumptions.
