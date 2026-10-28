# Next-agent handoff: study pipeline

This file is an operational handoff. The canonical implementation plan remains the work authority. I1 through I6, F1 through F23, the runtime-contract gate, and T1 through T5 are complete. No planned implementation slice remains.

## Worktree and branch

| Worktree                                         | Branch / current commit                                           | Meaning                                                                                                       |
| ------------------------------------------------ | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `/home/michalo/master_thesis-evaluation-rebuild` | `evaluation/rebuild` / current `HEAD`                         | Integration target. I1 through I6, F1 through F23, the runtime-contract gate, and T1 through T5 are complete. |
| `/home/michalo/master_thesis`                    | `main` / `8f9ede57369c38e7daf69ef23bd4727aa3742bbd`               | Primary worktree. Do not modify it during integration.                                                        |

Do not merge or cherry-pick the full candidate commit `70a2fa3`. Review candidate files only for selective reuse.

At handoff preparation time, the tracked worktree is clean. It contains only these untracked local files:

- `.pi/remote-pi/config.json`;
- `.pi/tmp/thesis-small-study-manual-e2e.md`; and
- `.pi/tmp/thesis-small-study-manual-e2e-results.md`.

The post-merge integration, deduplication, dependency, workspace, and documentation changes are committed. The merged main agent-tooling migration intentionally deleted `peru.yaml`. The generated verification files, external backup, and temporary safety stash were removed.

Preserve the two manual journey artifacts until their final disposition is decided. Review the local remote-agent configuration separately before staging.

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

- **Operational T1–T4 integration is complete** at `b1f83e0913e56373d6a95b9d13cc820a795a5ce1`. The coordinator runs one fixed Final tier DAG per tier, sequentially. Each run collects excluded warm-up `-1` and measured positions `0..4`, with configured environment checks and synchronous timing markers.
- Final collection keeps its scalar `gust_run_id` nil. Ordered `StudyPhaseRun` rows link one Gust run per tier. Compact collection references use ordered `gust_run_ids`; Pilot has a one-item list. Pilot and Final analysis references remain scalar.
- After all tiers finish, one canonical selector checks five complete-family non-timing summaries. Only replica `0` supplies the Final snapshot, which the coordinator creates outside Gust.
- **T5 is complete** at `0ecf5583b74b250b2bd737478b444a470134c3cb`. The coordinator validates Final elapsed intervals in memory. The compact result stores five measured values, median, minimum, and maximum for each tier and duration type. Raw monotonic readings and interval boundaries are not persisted. Detailed evidence stays in PostgreSQL snapshots and runtime records.
- **Post-merge integration is committed:** commit `76375e4edc9ccf5f7173794971c3a575e98329a4` merges local `main`. The follow-up commit removes all 108 ExDNA findings through 14 internal production helpers. It changes no test file and no lint policy. The schema-loading boundary also passes Sobelow without an exception. The dependency update pins `ex_slop` to `0.4.5`. The precommit dependency cleanup removed the unused `opentelemetry_req` lock entry.

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
- operational T1–T4 integration verification: 118 Chunk A/B checks, 298 study checks, and 635 evaluation checks passed;
- full Elixir suite after integration: 1,099 passed with two exclusions; both public journeys passed;
- integration checks cover ordered tier runs, complete-family equality, replica-zero evidence, cancellation at snapshot acceptance, and compact-reference read-back;
- T5 independent verification passed 24 pure timing checks, 19 result checks, 13 Final coordinator checks, both public journeys, 331 study checks, 668 evaluation checks, and the full suite with 1,132 passed and two exclusions;
- T5 verification also passed warning-as-error compilation, formatting, strict Credo, Dialyzer, contract generation without drift, and disposable-database teardown;
- manual `THESIS-E2E-01` and `THESIS-E2E-02` synthetic lifecycle journeys passed through the public lifecycle, real coordinator, collection-item execution, snapshots, compact-result persistence, and typed timing read-back;
- manual journey isolation used 40 application migrations and 12 Gust migrations on one disposable database; the temporary harness and database were removed, and the final worktree status matched the initial status;
- the unrelated Family Gust restart characterization passed in three isolated runs after an earlier timing-sensitive failure;
- formatting, warning-as-error compilation, strict Credo, Dialyzer, Ruff, schema drift, frontend type checks, and diff checks passed for their applicable slices. The integration verification also passed forced warning-as-error compilation, strict Credo, Dialyzer, and contract generation without drift;
- post-merge deduplication verification passed the guarded full precommit suite with 1,158 tests passed, zero failed, and two existing RabbitMQ exclusions;
- the final precommit run passed formatting, warning-as-error compilation, strict Credo with zero findings, Dialyzer, Sobelow, frontend formatting and type checks, client and server builds, and contract generation without drift;
- final database verification applied 40 application migrations and 12 Gust migrations. Both repositories used one fresh disposable database. Teardown left no database and zero connections;
- an independent review covered 53 modified production files and 14 new helpers. It found no actionable regression. The review also passed 180 existing pure tests;
- no test file was added or changed during the deduplication.

## Approved prototype scope

The user reviewed each plan chunk and approved the simplified structure.

Key decisions:

- Merge I3+I4 and I5+I6.
- Remove I7–I13 as standalone durable-infrastructure chunks.
- Use one supervised ephemeral coordinator task.
- Do not add an Oban lifecycle handoff, periodic poller, automatic restart recovery, or phase replay.
- Use Gust completion callbacks only as non-authoritative wake-up signals. Persisted Gust rows remain authoritative.
- Persist one row for each fixed study phase. Final collection links its ordered tier-run family through `StudyPhaseRun` rows, not one scalar Gust run.
- If the application restarts during active coordination, the execution can remain stuck. The operator cancels it and starts a new execution.
- Store compact results only for successful executions.
- Keep `pilot_override` null before resume, false for a recommendation, and true for an insufficient override.
- Use the accepted Pilot analysis phase as the lifecycle source. Bind its persisted Gust run at every Final analysis boundary.
- Add only `study_execution_id` to the strict Final request. Load the candidate, override marker, and accepted phase records from PostgreSQL.
- Start no Final coordinator shell in F16+F17+F18. F19+F20+F21 start the real coordinator after the resume transaction commits.
- Direct Pilot and Final facade functions are retired. Their modules remain internal to the study coordinator.
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

- T1–T5 timing collection, summary construction, compact-result persistence, and read-back are complete.
- Run tiers sequentially.
- Use warm-up replica `-1` and measured replicas `0..4`.
- Replica `0` supplies Final evidence after all measured replicas pass equivalence.
- Use `System.monotonic_time(:microsecond)` in the Final coordinator VM.
- Include Gust and ScatterGather wait time in elapsed intervals.
- Measure total directly; do not add plan-selection and simulation spans.
- Read the current measured-environment assertion from application configuration.
- Compare it before warm-up and before and after each measured replica.
- Add no fingerprint, UTC substitute, or replica retry epoch.
- The coordinator validates five measured records per tier in memory. Each record contains plan-selection, simulation, and total elapsed intervals.
- The compact result stores the five values, median, minimum, and maximum for each duration in declared tier order.
- The tiny controlled timed journeys passed. They checked warm-up exclusion, measured positions, replica-zero evidence, summaries, and read-back without asserting real elapsed durations.

## Manual thesis-like lifecycle evidence

Two controlled manual journeys passed against commit `0ecf5583b74b250b2bd737478b444a470134c3cb`:

- `THESIS-E2E-01`: a controlled Pilot recommendation paused at `awaiting_final`, resumed with `:recommended`, and completed with `pilot_override: false`.
- `THESIS-E2E-02`: a controlled insufficient Pilot rejected `:recommended` without changing stored state, accepted `{:override_insufficient, "medium"}`, and completed with `pilot_override: true`.

Both journeys used the public lifecycle functions. They verified:

- state progression through Pilot pause, Final collection, and success;
- `result_unavailable` before Final success;
- four fixed phase rows: `pilot_collection`, `pilot_analysis`, `final_collection`, and `final_analysis`;
- ordered Final tier runs for `core` and `edge`;
- replica positions `-1` and `0..4`;
- separate Pilot and Final snapshots;
- one immutable compact result;
- Final family `family-example` with two comparisons;
- per-tier plan-selection, simulation, and total timing summaries.

The manual fixture stores candidate `medium` with 6 plans per side and 10 attacks per plan. The source study fixture declares 12 attacks, but `StudyFixtures.conformance_journey_definition!/2` aligns the manual journey with the checked-in Final conformance fixture, which contains 10 attacks per plan.

Evidence boundary:

- These runs are synthetic lifecycle evidence with Gust transport seams.
- The public facade, coordinator, lifecycle, collection items, snapshots, persistence, validation, and read-back were real application boundaries.
- Gust run transport and Pilot/Final analysis results used controlled seams.
- These runs are not real Gust end-to-end evidence and are not scientific thesis evidence.

Manual artifacts:

- `.pi/tmp/thesis-small-study-manual-e2e.md`;
- `.pi/tmp/thesis-small-study-manual-e2e-results.md`.

## Verification policy

Use a reasonable set of unit and integration tests for each risk:

- unit tests for deterministic scientific and lifecycle logic;
- repository tests for uniqueness and transactional create-and-link behavior;
- selected integration tests for Gust boundaries and coordinators;
- two automated core journeys: recommended and insufficient override;
- one manual timed journey.

The EARS entries define behaviors, not an exact test count. Use shared fixtures for common setup and request data. Do not add source, AST, schema-layout, helper, or manifest tests. Do not add exhaustive malformed-input, mutation, or state-pair matrices. Do not duplicate a behavior across test layers without a separate risk.

Every database-backed test invocation needs a fresh partition and disposable database. Prepare both application and Gust migrations. Verify both repositories use the disposable database. Drop it afterward. Never run an unpartitioned `mix test` or `mix run` against preserved data.

## Next action

The canonical implementation plan is complete. Close out the prototype before any new feature work:

1. Keep the accepted implementation and documentation synchronized.
2. Preserve the prototype limits and recorded verification evidence.
3. Require a separate approved plan for deployment, real evidence collection, automatic recovery, replay, replacement replicas, or UI expansion.

Preserve unrelated user changes. Do not deploy, push, collect real evidence, or modify the primary worktree.
