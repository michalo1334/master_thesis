# Chunk 09: Automated Verification

## Objective

Verify generated output, backend behavior, frontend behavior, and static quality after the refactor.

## Scope

- Run the Svelte autofixer on every changed `.svelte`, `.svelte.ts`, and `.svelte.js` file, then apply valid suggestions.
- Run contract generation twice and confirm stable output.
- Search for old contract module and TypeScript alias names.
- Search for duplicate geometry, traversal, and gesture helpers targeted by the review.
- Run full backend and frontend automated checks.
- Confirm unrelated `.pi/**` changes remain untouched.

## Acceptance

- Contract generation has no drift.
- Backend and frontend test suites pass.
- The Svelte autofixer reports no unresolved issue in changed Svelte files.
- Formatting, compile warnings, Svelte checks, typecheck, and configured static analysis pass.
- No stale old contract alias remains.

## Checks

Use the repository check commands and the command-runner workflow required by `AGENTS.md`. Record exact pass counts and excluded tests.
