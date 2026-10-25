# Next-agent handoff: study pipeline

This file is an operational handoff. The canonical implementation plan remains the work authority. I3+I4 source implementation is complete. The next scheduled slice is I5+I6.

## Worktree and branch

| Worktree                                         | Branch / current commit                             | Meaning                                                |
| ------------------------------------------------ | --------------------------------------------------- | ------------------------------------------------------ |
| `/home/michalo/master_thesis-evaluation-rebuild` | `evaluation/rebuild` / current `HEAD`               | Integration target. I1 through I4 are complete.        |
| `/home/michalo/master_thesis`                    | `main` / `8f9ede57369c38e7daf69ef23bd4727aa3742bbd` | Primary worktree. Do not modify it during integration. |

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
- **I5 onward is not implemented.**

Recorded checks:

- I1+I2 focused suite: 69 passed;
- I3+I4 focused persistence suite: 2 passed;
- complete study test directory after I3+I4: 71 passed;
- normal commit hook after I3+I4: 822 passed with two existing exclusions;
- formatting and normal static, frontend, and security checks passed.

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

Use the smallest check that protects a distinct risk:

- unit tests for deterministic scientific and lifecycle logic;
- repository tests for uniqueness and transactional create-and-link behavior;
- selected integration tests for Gust boundaries and coordinators;
- two automated core journeys: recommended and insufficient override;
- one manual timed journey.

Do not add source, AST, schema-layout, helper, or manifest tests. Do not add exhaustive malformed-input, mutation, or state-pair matrices. Do not duplicate a behavior across test layers without a separate risk.

Every database-backed test invocation needs a fresh partition and disposable database. Prepare both application and Gust migrations. Verify both repositories use the disposable database. Drop it afterward. Never run an unpartitioned `mix test` or `mix run` against preserved data.

## Next implementation action

When the user authorizes implementation:

1. Recheck repository instructions and dirty state.
2. Implement merged I5+I6 only.
3. Add one table-driven valid-transition test, representative invalid-transition cases, and one duplicate-phase repository case.
4. Run focused tests and the nearest regressions in a disposable database.
5. Stop when the chunk is green.

Preserve unrelated user changes. Do not deploy, push, collect real evidence, or modify the primary worktree.
