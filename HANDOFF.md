# Next-agent handoff: study pipeline

This file is an operational handoff. The canonical implementation plan remains the work authority. F1 through F23 and the runtime-contract gate are complete. T1+T2 are next.

## Worktree and branch

| Worktree                                         | Branch / current commit                             | Meaning                                                                                        |
| ------------------------------------------------ | --------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `/home/michalo/master_thesis-evaluation-rebuild` | `evaluation/rebuild` / current `HEAD`               | Integration target. I1 through I6, F1 through F23, and the runtime-contract gate are complete. |
| `/home/michalo/master_thesis`                    | `main` / `8f9ede57369c38e7daf69ef23bd4727aa3742bbd` | Primary worktree. Do not modify it during integration.                                         |

Do not merge or cherry-pick the full candidate commit `70a2fa3`. Review candidate files only for selective reuse.

## Authority

Read these files before implementation:

1. [Implementation plan](docs/design/evaluation-study-pipeline-implementation-plan.md)
2. [Target design](docs/design/evaluation-study-pipeline.md)
3. [Deferred runtime contract](docs/design/evaluation-study-runtime-contract-future-work.md)
4. [Scientific methodology](docs/concepts/evaluation-methodology.md)
5. [Vocabulary](docs/concepts/vocabulary.md)
6. [Decision history](docs/history/evaluation-decisions.md)

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
- **F5+F6+F7 are complete:** Pilot uses one ordered candidate list. Stable candidate IDs and exact counts pass through mapped work, Python computation, stored rows, summaries, recommendations, and public read-back. Declared position remains internal as the final tie-break. The removed grid shape is rejected before Gust run creation.
- **F8+F9 are complete:** one deterministic Pilot builder emits comparison-side-plan work for one replica. It uses the required seed prefix and phase-item cap. One mapped action uses F4 reservations and returns compact runtime IDs and completion counts.
- **F10+F11 are complete:** each completed simulation trial stores measured monotonic runtime in microseconds. Pilot runtime assembly uses persisted optimization and trial durations and converts them to floating-point milliseconds at the snapshot boundary.
- **F12+F13 are complete:** Pilot fan-in locks the persisted phase, reloads the exact replica-zero collection rows, validates linked runtime identity and completeness, restores declared order, and creates or returns one phase-linked snapshot.
- **The runtime-contract gate is complete:** typed optimization and simulation requests materialize closed values as atoms and persist all effective scientific settings. Runtime execution rebuilds typed requests from stored records. The mapped collection action accepts only a collection-item ID, reloads the immutable study revision, and rebuilds canonical work before reservation.
- **F14+F15 are complete:** one supervised temporary task runs Pilot collection and analysis. Fixed Gust DAGs use bounded callbacks as wake-up signals. Persisted Gust rows remain authoritative. The coordinator stores one compact recommendation or insufficiency outcome and stops at `awaiting_final`.
- **F16+F17+F18 are complete:** the internal resume command locks a paused execution, validates the tagged selection, stores one typed frozen candidate and override, enters `collecting_final`, and creates or reuses one empty Final collection phase. Shared binding reloads authoritative state and compares one typed Final source.
- **F19+F20+F21 are complete:** the Final coordinator collects fresh Final work with separate seeds and roots, links one Final snapshot, runs lifecycle-bound complete-family analysis, stores one immutable compact result, and enters `succeeded`. The strict Final request adds only `study_execution_id`. Every Final analysis boundary reloads the frozen selection and accepted phase records from PostgreSQL.
- **F22+F23 are complete:** the six public study lifecycle functions are active. Start creates the execution and Pilot collection phase atomically. The coordinator creates each analysis phase at its accepted handoff. Cancellation is locked and idempotent for cancelled executions. Result read-back returns one typed compact result only after success. Direct Pilot and Final facade groups are removed; comparison and family APIs remain.

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
- F5+F6+F7 affected Elixir Pilot suite: 84 passed;
- full suite after F5+F6+F7: 845 passed with two existing exclusions;
- full Python evaluation-compute suite after F5+F6+F7: 135 passed;
- F8+F9 focused collection and runtime-configuration suite: 26 passed;
- complete study test directory after F8+F9: 95 passed;
- evaluation regression suite after F8+F9: 422 passed;
- the F8+F9 full-suite run passed 857 tests with two exclusions and one unrelated timing failure; that timing case passed three times in isolation;
- F10–F13 focused runtime and fan-in suite: 29 passed;
- evaluation regression suite after F10–F13: 433 passed;
- full suite after F10–F13: 874 passed with two exclusions;
- runtime-contract gate full Elixir suite: 899 passed with two exclusions;
- runtime-contract gate frontend suite: 578 passed;
- independent runtime-contract fresh-database regression suite: 333 passed;
- complete study test directory after F14+F15: 144 passed;
- Pilot workflow regression suite after F14+F15: 11 passed;
- independent F16+F17+F18 selection and binding suite: 34 passed;
- independent Final and study regression suite after F19+F20+F21: 270 passed;
- F22+F23 focused activation and journey suite: 63 passed;
- F22+F23 Study, Pilot, Final, and Family regression suites: 474 passed;
- F22+F23 contract drift suite: 13 passed;
- formatting, warning-as-error compilation, strict Credo, Dialyzer, Ruff, schema drift, frontend type checks, and diff checks passed for their applicable slices.

## Approved prototype scope

The user reviewed each plan chunk and approved the simplified structure.

Key decisions:

- Merge I3+I4 and I5+I6.
- Remove I7–I13 as standalone durable-infrastructure chunks.
- Use one supervised ephemeral coordinator task.
- Do not add an Oban lifecycle handoff, periodic poller, automatic restart recovery, or phase replay.
- Use Gust completion callbacks only as non-authoritative wake-up signals. Persisted Gust rows remain authoritative.
- Persist one row for each fixed study phase and its Gust run.
- If the application restarts during active coordination, the execution can remain stuck. The operator cancels it and starts a new execution.
- Store compact results only for successful executions.
- Keep `pilot_override` null before resume, false for a recommendation, and true for an insufficient override.
- Use the accepted Pilot analysis phase as the lifecycle source. Bind its persisted Gust run at every Final analysis boundary.
- Add only `study_execution_id` to the strict Final request. Load the candidate, override marker, and accepted phase records from PostgreSQL.
- Start no Final coordinator shell in F16+F17+F18. F19+F20+F21 start the real coordinator after the resume transaction commits.
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

Prepare T1+T2 as one timing-foundation slice:

1. Recheck repository instructions and dirty state.
2. Define the typed schedule for warm-up replica `-1` and measured replicas `0` through `4` for each tier.
3. Keep tiers sequential.
4. Define monotonic microsecond intervals for plan selection, simulation, and total elapsed work.
5. Measure each interval from its own boundaries. Do not calculate total by adding overlapping intervals.
6. Limit clock injection to the small interval function used by its unit test.
7. Keep T3+T4 environment and equivalence gates, T5 summaries, deployment, recovery, replay, polling, and UI work out of scope.

Preserve unrelated user changes. Do not deploy, push, collect real evidence, or modify the primary worktree.
