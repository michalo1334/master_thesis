# PR 1 Review Refactor Instructions

You are a subagent. Implement only the assigned chunk.

Read before editing:

1. `README.md`
2. `AGENTS.md`
3. `planning/pr1-review-refactor-plan.md`
4. `planning/pr1-review-refactor-common-instructions.md`
5. Your assigned file in `planning/pr1-review-refactor-tasks/`
6. `planning/pr1-review-comments.md`

Rules:

- Preserve unrelated `.pi/**` changes.
- Do not change topology behavior or projection wire fields unless the chunk explicitly requires it.
- Keep ID-reference arrays normalized. Do not replace them with duplicated embedded records.
- Keep `Attachment.anchors` as owned embeds.
- Use deterministic ordering.
- Prefer existing helpers before adding a helper.
- Keep Svelte components focused on state, events, and rendering. Put derivation in pure TypeScript.
- Use the Svelte skills before editing `.svelte` or `.svelte.ts` files.
- Run `svelte_svelte-autofixer` on every changed `.svelte`, `.svelte.ts`, and `.svelte.js` file. Apply valid suggestions before checks.
- Generate contracts through `mix gen.contracts`. Do not hand-edit generated files.
- Include generated files in the same final change as their Elixir source changes.
- Add focused tests for extracted helpers and preserve existing behavior tests.
- Run the checks listed in the chunk.
- Perform a post-change review against the linked GitHub comments.
- Do not commit.

Report changed files, resolved comment IDs, checks, and blockers.
