# Phase 3 Model Comparison Handoff

## Status

Phase 3 is implemented. One schema-version-3 manifest can declare multiple
model variants, execute their plans against one graph and attack-seed schedule,
export one ZIP, and analyze strategy and model comparisons.

The design and execution record is in
`docs/plans/phase-3-model-comparison.md`.

## Completed

- Replaced the singular manifest model with named model variants.
- Added model-aware strategy runs and comparison selectors.
- Made the plan identity model variant, strategy, budget, and selection seed.
- Updated evaluation persistence and resume uniqueness.
- Added blast-radius-only, mission-impact-only, and mission-then-blast-radius
  objective ranking.
- Made pre-attack feasibility configurable at strategy and optimizer layers.
- Passed model settings through evaluation plan selection and execution.
- Added model settings to `plans.jsonl` without repeating them in trial CSVs.
- Kept all plans on one ordered attack-evaluation seed schedule.
- Updated Python validation, pairing, tables, CDFs, figures, and metadata for
  model-aware comparisons.
- Updated Elixir and generated TypeScript dashboard contracts.
- Updated the manifest editor default and analysis report model labels.
- Updated the Phase 1, Phase 2, and evaluation-roadmap documents.

## Contract

New manifests and analysis ZIPs require schema version 3. Version 2 compatibility
was intentionally removed.

The original evaluation migration was changed retroactively. Reset an existing
local database before running the new schema. Do not add a legacy backfill path
unless persisted historical data becomes a concrete requirement.

## Verification

- Elixir: 426 tests passed.
- Python analysis: 62 tests passed.
- Frontend: 373 tests passed.
- Svelte type checking: no errors or warnings.
- Credo: passed when run with compilation in the same Mix invocation.
- Dialyzer: passed.
- Sobelow: passed.
- Asset build: passed.
- Svelte autofixer: no findings for `AnalysisReport.svelte`.
- `git diff --check`: passed.

`mix precommit` remains blocked by unrelated formatting in
`src/lib/network_defense_web.ex`. The formatter expects a blank line after the
local `log` assignment in `live_view/0`. That file already had user changes and
was not modified for Phase 3.

Existing unrelated warnings remain for two unused functions in
`dashboard_live.ex`.

## Worktree

The worktree contains unrelated user changes. Do not revert, stage, or commit
them as part of Phase 3. Use `git status --short` and inspect the Phase 3 diff
before staging anything.

## Next Actions

1. Resolve or approve formatting of `src/lib/network_defense_web.ex`.
2. Run `mix precommit` from `src/`.
3. Reset the local database and apply the retroactively changed migrations.
4. Run a reviewed, small schema-version-3 manifest through evaluation and
   analysis in the local stack.
5. Inspect the ZIP for distinct model-aware plans, matched attack seeds, and
   separate model-variant result groups.
6. Commit only the intended Phase 3 files when requested.
