# Next-agent handoff: study pipeline

This file is an operational handoff. The canonical implementation plan remains the work authority. F1 through F4 are complete. The next slice is F5+F6+F7.

## Worktree and branch

| Worktree                                         | Branch / current commit                             | Meaning                                                           |
| ------------------------------------------------ | --------------------------------------------------- | ----------------------------------------------------------------- |
| `/home/michalo/master_thesis-evaluation-rebuild` | `evaluation/rebuild` / current `HEAD`               | Integration target. I1 through I6 and F1 through F4 are complete. |
| `/home/michalo/master_thesis`                    | `main` / `8f9ede57369c38e7daf69ef23bd4727aa3742bbd` | Primary worktree. Do not modify it during integration.            |

Do not merge or cherry-pick the full candidate commit `70a2fa3`. Review candidate files only for selective reuse.

## Authority

Read these files before implementation:

1. [Implementation plan](docs/design/evaluation-study-pipeline-implementation-plan.md)
2. [Target design](docs/design/evaluation-study-pipeline.md)
3. [Scientific methodology](docs/concepts/evaluation-methodology.md)
4. [Vocabulary](docs/concepts/vocabulary.md)
5. [Decision history](docs/history/evaluation-decisions.md)

The plan retains every original ID for traceability. It merges related IDs and marks removed infrastructure IDs explicitly.

## Implemented state

- **I1 is complete:** bounded `YamlElixir` wrapper, safe JSON normalization, bounded errors, and 25 focused YAML cases.
- **I2 is complete:** strict JSON Schema validation before Ecto materialization, normalized round-trip data, and scientific cross-field checks.
- **I3+I4 are complete:** `create_study_revision/1` parses and validates YAML, resolves graph revisions, stores one normalized immutable revision, and returns bounded reference, conflict, or storage errors.
- **I5+I6 are complete:** the pure lifecycle defines accepted transitions and idempotent terminal handling. Study executions and fixed phases have persisted closed sets and phase uniqueness.
- **F1 is complete:** every typed optimization request carries one concrete top-level seed. Every strategy receives and persists it. Resume identity includes the graph revision, strategy, budget, seed, and simulation configuration. The dashboard exposes seed entry and random generation for every strategy.
- **F2 is complete:** each fixed study phase has stable collection items keyed by replica and item position.
- **F3 is complete:** `Simulations.prepare/1` validates and stores one running experiment without starting simulation work.
- **F4 is complete:** short locked transactions create or reuse linked optimization runs and experiments. Shared preparation validates requests before locking. Mismatched links remain unchanged.
- **F5 onward is not implemented.**

Recorded checks:

- I1+I2 focused suite: 69 passed;
- I3+I4 focused persistence suite: 2 passed;
- I5+I6 focused suite: 3 passed;
- complete study test directory after I5+I6: 74 passed;
- full suite after I5+I6: 825 passed with two existing exclusions;
- F1 focused suite: 29 passed;
- F1 optimization and dashboard regression suite: 152 passed;
- touched F1 frontend suite: 127 passed;
- F2 collection-item persistence suite: 4 passed;
- F3 simulation suite: 17 passed;
- F4 reservation and collection-item suite: 12 passed;
- optimization regression suite after F4: 62 passed;
- complete study test directory after F4: 86 passed;
- full suite after F4: 842 passed with two existing exclusions;
- formatting, compilation, Credo, Dialyzer, and frontend type checks passed.

## Approved prototype scope

The user reviewed each plan chunk and approved the simplified structure.

Key decisions:

- Merge I3+I4 and I5+I6.
- Remove I7–I13 as standalone durable-infrastructure chunks.
- Use one supervised ephemeral coordinator task.
- Do not add an Oban lifecycle handoff, callback, poller, automatic restart recovery, or phase replay.
- Persist one row for each fixed study phase and its Gust run.
- If the application restarts during active coordination, the execution can remain stuck. The operator cancels it and starts a new execution.
- Store compact results only for successful executions.
- Retire all direct Pilot and Final facade functions when the complete study lifecycle activates.
- Keep lower-level comparison and family APIs.
- Keep fixed Gust phase DAGs, ScatterGather trial batches, and synchronous stateless Python computation.

The approved public study facade is:

- `create_study_revision/1`;
- `start_study/1`;
- `study_status/1`;
- `resume_study/2`;
- `cancel_study/1`; and
- `study_result/1`.

`resume_study/2` accepts `:recommended` or `{:override_insufficient, candidate_id}`. The application derives `pilot_override`.

## Scientific constraints

- No new scientific defaults.
- Only graph revisions have immutable application records and loaders.
- Other revision strings are bounded caller assertions.
- Every typed optimization request has one concrete seed for every strategy.
- Dashboard random-seed generation finishes before typed optimization parsing.
- Preserve separate optimization-scoring and evidence-simulation profiles.
- Preserve declared candidate and family order.
- Use the first required selection seeds in declared order.
- Preserve maximum-budget semantics.
- Preserve independent plan rows and shared ordered attack columns.
- Preserve the existing child-seed policy.
- Apply one Holm correction to the complete Final family.
- Always pause after valid Pilot analysis.
- Invalid or failed Pilot cannot resume.
- Insufficient Pilot requires `{:override_insufficient, candidate_id}` for a declared candidate.

## Timing decisions

- Run timing last.
- Run tiers sequentially.
- Use warm-up replica `-1` and measured replicas `0..4`.
- Replica `0` supplies Final evidence after all measured replicas pass equivalence.
- Use `System.monotonic_time(:microsecond)` in the Final coordinator VM.
- Include Gust and ScatterGather wait time in elapsed intervals.
- Measure total directly; do not add plan-selection and simulation spans.
- Read the current measured-environment assertion from application configuration.
- Compare it before warm-up and before and after each measured replica.
- Add no fingerprint, UTC substitute, or replica retry epoch.
- Store five measured values, median, minimum, and maximum for each duration.
- Verify the complete timed journey manually. Keep pure schedule, interval, equivalence, environment, and summary checks automated.

## Verification policy

Use a reasonable set of unit and integration tests for each risk:

- unit tests for deterministic scientific and lifecycle logic;
- repository tests for uniqueness and transactional create-and-link behavior;
- selected integration tests for Gust boundaries and coordinators;
- two automated core journeys: recommended and insufficient override;
- one manual timed journey.

The EARS entries define behaviors, not an exact test count. Use shared fixtures for common setup and request data. Do not add source, AST, schema-layout, helper, or manifest tests. Do not add exhaustive malformed-input, mutation, or state-pair matrices. Do not duplicate a behavior across test layers without a separate risk.

Every database-backed test invocation needs a fresh partition and disposable database. Prepare both application and Gust migrations. Verify both repositories use the disposable database. Drop it afterward. Never run an unpartitioned `mix test` or `mix run` against preserved data.

## Next implementation action

When the user authorizes implementation:

1. Recheck repository instructions and dirty state.
2. Implement F5+F6+F7 only.
3. Replace the Pilot Cartesian candidate grid with the ordered declared candidate list.
4. Carry each stable candidate ID through work and results.
5. Return the candidate ID and selected counts in recommendations. Do not expose declared position.
6. Reject the removed grid field before Gust submission.
7. Cover the cutover with reasonable contract, analysis, and integration tests.
8. Run focused tests and the nearest regressions in a disposable database.
9. Stop when the chunk is green.

Preserve unrelated user changes. Do not deploy, push, collect real evidence, or modify the primary worktree.
