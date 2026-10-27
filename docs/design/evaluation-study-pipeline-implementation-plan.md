# Evaluation study pipeline implementation plan

## Scope

This plan implements the target in [evaluation-study-pipeline.md](evaluation-study-pipeline.md). It defines a working prototype, not a production workflow service.

The plan has four slices:

1. **Definition foundation:** parse and validate one complete study definition.
2. **Revision and lifecycle model:** store immutable revisions and the minimal execution state.
3. **Core outcome path:** collect Pilot and Final evidence, pause, resume, and store one compact result.
4. **Timing:** add the required warm-up and five measured replicas.

This plan does not authorize deployment, real evidence collection, UI work beyond preserving the optimization controls, or new scientific defaults.

## Current branch status

The current `evaluation/rebuild` branch contains I1 through I6 and F1 through F23. F22+F23 activate the six public study lifecycle functions and retire the direct Pilot and Final facade groups.

The [runtime-contract gate](evaluation-study-runtime-contract-future-work.md) and operational T1–T4 integration are complete. Final collection runs sequential tier DAGs with excluded warm-up `-1`, measured positions `0..4`, coordinator elapsed intervals, and environment gates. One canonical selector checks five complete-family summaries before the coordinator creates the replica-zero snapshot. Ordered tier rows supply Final collection's run-ID list; its scalar run ID remains nil. Timings are validated in memory only.

T5 is next: timing summaries, compact-result timing persistence, and the manual timed journey. Compact-result timing remains nil. The slice descriptions and acceptance cases below retain their original implementation sequence; they are not a second current-state reference.

## Prototype boundaries

The prototype uses one supervised application task to coordinate study phases. Gust persists work inside each phase. Gust completion callbacks send non-authoritative wake-up signals to temporary waiters. The application does not add an Oban lifecycle worker, periodic polling, automatic restart recovery, or phase replay.

An application restart can leave an active execution without a coordinator. The operator cancels that execution and starts a new one.

The prototype also excludes:

- a workflow framework or DAG compiler;
- compatibility readers and format adapters;
- domain-revision registries or authenticated provenance;
- automatic revision numbering;
- failed or cancelled study-result records;
- cross-deployment recovery;
- deployment and real study execution.

## Destructive cutover policy

For each changed contract:

1. Switch all repository producers, readers, fixtures, and tests together.
2. Delete the replaced shape and its tests.
3. Reject the removed shape before Gust work starts.
4. Add no adapter, dual reader, or fallback.

At public lifecycle activation, remove the direct Pilot and Final facade functions. Keep their implementation modules internal to the study coordinator. Keep the lower-level comparison and family APIs.

## Public Elixir interface

The completed prototype exposes these functions through `NetworkDefense.Evaluations`:

```elixir
@spec create_study_revision(binary()) ::
        {:ok, StudyRevision.t()} | {:error, StudyError.t()}

@spec start_study(Ecto.UUID.t()) ::
        {:ok, StudyExecution.t()} | {:error, StudyError.t()}

@spec study_status(Ecto.UUID.t()) ::
        {:ok, StudyExecution.t()} | {:error, StudyError.t()}

@type final_selection ::
        :recommended
        | {:override_insufficient, candidate_id :: String.t()}

@spec resume_study(Ecto.UUID.t(), final_selection()) ::
        {:ok, StudyExecution.t()} | {:error, StudyError.t()}

@spec cancel_study(Ecto.UUID.t()) ::
        {:ok, StudyExecution.t()} | {:error, StudyError.t()}

@spec study_result(Ecto.UUID.t()) ::
        {:ok, Study.CompactResult.t()} | {:error, StudyError.t()}
```

`cancel_study/1` is idempotent for an already-cancelled execution. It rejects `succeeded` and `failed` executions with the bounded conflict reason `study_execution_not_cancellable`.

`study_result/1` returns a bounded `result_unavailable` error until a successful result exists. It returns the typed compact result and never the `StudyResult` persistence row. It never returns a partial result.

## Test policy

The EARS entries define required behaviors. They do not define an exact test count. Add a reasonable set of unit and integration tests for the risks in each chunk. Use shared fixtures for common setup and request data.

Use automated tests for:

- deterministic scientific logic;
- strict input contracts;
- database uniqueness and create-and-link transactions;
- Gust phase boundaries;
- the recommended and insufficient-override core journeys.

Use manual checks for:

- ordinary status inspection;
- cancellation and failure display;
- operator-facing API use;
- the complete timed journey.

Do not add source-text, AST, schema-layout, helper, or manifest tests. Do not add exhaustive malformed-input or state-transition matrices. Do not prove one behavior again at unit, integration, and journey levels without a separate risk. Use parameterized cases or shared fixtures when tests repeat the same setup.

Every database-backed test run must use a fresh test partition and disposable database. Prepare application and Gust migrations, pin both repositories to that database, and drop it after the run.

## Slice 1 — definition foundation

### I1 — YAML boundary — complete

**Internal interface:** `NetworkDefense.Evaluation.Study.Yaml.parse/1`.

The wrapper parses one bounded YAML string with string keys and returns one JSON-compatible map or bounded error. It stores no source YAML.

The existing 25-case YAML suite is sufficient. Add no cases.

### I2 — complete definition contract — complete

**Internal interfaces:** `Definition.parse/1` and `Definition.to_params/1`.

The checked-in schema and typed embedded contracts require all scientific settings, ordered candidates, seed roles, graph references, and reproduction assertions.

The existing definition suite is sufficient. Add no cases.

## Slice 2 — revision and lifecycle model

### I3 + I4 — revision persistence and facade — complete

**Public interface:** `NetworkDefense.Evaluations.create_study_revision/1`.

**Implementation hints:**

- Parse YAML and the typed definition.
- Resolve every graph revision before insertion.
- Treat all other revision strings as bounded caller assertions.
- Store the schema version, declared study ID, declared revision number, normalized definition, and insertion time.
- Enforce one row for each `(study_id, revision)` pair.
- Return the inserted `StudyRevision` struct.
- Do not compare content or return an existing row after a duplicate declaration.

**EARS — integration:**

> WHEN valid YAML references existing graph revisions, THE application SHALL store one normalized immutable revision and return that revision.

**EARS — integration:**

> WHEN any referenced graph revision does not exist, THE application SHALL return a bounded error and store no revision.

### I5 + I6 — lifecycle model and persistence — complete

**Internal interface:**

```elixir
@spec initial_state() :: :collecting_pilot
@spec transition(state(), event()) :: {:ok, state()} | {:error, :invalid_transition}
```

**Implementation hints:**

- Persist one `StudyExecution` with revision ID, state, optional terminal error, and timestamps.
- Persist one `StudyPhase` for each fixed phase.
- A phase stores its Gust run ID, accepted snapshot or result reference, bounded error, and timestamps.
- Enforce one row for each `(execution_id, phase)` pair.
- Add candidate, Pilot-outcome, and override fields only when their behavior becomes active.
- Do not add attempt numbers, replay lineage, or an active-attempt pointer.
- Only active phases can fail. `awaiting_final` can resume, remain paused, or cancel.

**EARS — unit:**

> WHEN the lifecycle receives each accepted phase event, THE lifecycle SHALL return its declared next state.

Use table-driven coverage for accepted transitions.

**EARS — unit:**

> WHEN an event is invalid for the current state, THE lifecycle SHALL return `:invalid_transition`.

Use representative invalid cases, not a complete state/event matrix.

**EARS — repository integration:**

> WHEN an execution already has a row for one phase, THE repository SHALL reject a second row for that execution and phase.

### Removed infrastructure IDs

| ID  | Disposition                                                                                             |
| --- | ------------------------------------------------------------------------------------------------------- |
| I7  | Absorbed into the real Pilot and Final coordinator chunks. There is no standalone command/outbox chunk. |
| I8  | Removed. There is no lifecycle envelope cutover.                                                        |
| I9  | Removed. There is no correlated Gust-run recovery.                                                      |
| I10 | Removed. There is no Oban dispatch or status worker.                                                    |
| I11 | Typed validation is part of each real phase handoff. There is no generic acceptance framework.          |
| I12 | Removed. Failed and cancelled executions have no compact result.                                        |
| I13 | Removed. Real Pilot and Final paths replace the controlled skeleton.                                    |

## Slice 3 — core outcome path

### F1 — explicit optimization seed — complete

**Public function signatures:** unchanged in `NetworkDefense.Optimizations`.

The typed `OptimizationParams` adds one required concrete seed for every strategy. An explicit zero remains valid.

**Implementation hints:**

- Pass the seed to every strategy constructor.
- Persist it in `OptimizationRun`.
- Remove the random-strategy zero fallback.
- Check graph revision, strategy, budget, seed, and simulation configuration before resume.
- Keep the dashboard Seed field and Random seed option.
- Resolve dashboard random generation before `RunOptimizationRequest` parsing.
- The study path always supplies its declared seed.

**EARS — contract unit:**

> WHEN an optimization request has no seed, THE request SHALL fail validation.

**EARS — integration:**

> WHEN a valid request is prepared, THE optimization run SHALL store the declared seed.

**EARS — integration:**

> WHEN resume changes the graph revision, strategy, budget, or seed, THE optimization SHALL reject the changed request.

Use shared fixtures for the common request and persisted-run setup. Cover each changed resume-identity field without testing every combination.

### F2 — stable positional collection item — complete

**Internal interface:**

```elixir
@spec get_or_create(study_phase_id, replica_position, item_position) ::
        {:ok, StudyCollectionItem.t()} | {:error, StudyError.t()}
```

The item stores its phase, replica position, item position, optional optimization-run ID, optional experiment ID, and timestamps.

Enforce one row for each `(study_phase_id, replica_position, item_position)` tuple. The immutable definition and deterministic work order define the position. Do not copy the full scientific identity into the unique key.

**EARS — repository integration:**

> WHEN the same phase, replica, and item position is requested again, THE application SHALL return the same collection item, while another phase receives a different item.

### F3 — synchronous simulation preparation — complete

**Public interface:**

```elixir
@spec NetworkDefense.Simulations.prepare(RunSimulationRequest.t()) ::
        {:ok, Experiment.t()} | {:error, Simulations.Errors.error()}
```

The function validates the graph, foothold, and feasibility. It inserts one running experiment with zero completed trials. It starts no process and no ScatterGather work.

`run_async/1` can reuse `prepare/1`. Study collection stores the prepared experiment ID and then calls `run/2`.

**EARS — integration:**

> WHEN a valid simulation request is prepared, THE application SHALL store one running experiment with zero completed trials and SHALL start no simulation work.

Existing simulation tests cover invalid graph and model inputs. Do not repeat them.

### F4 — two-stage runtime reservation — complete

**Internal interfaces:**

```elixir
reserve_optimization(item_id, optimization_request)
reserve_experiment(item_id, simulation_request)
```

Each function locks the collection item for one short transaction. It creates and links one domain record or returns the existing matching link. Computation runs after commit.

The collection action follows this sequence:

1. Reserve the optimization run.
2. Run or resume optimization outside the transaction.
3. Build the simulation request from the optimized graph.
4. Reserve the experiment.
5. Run or resume simulation outside the transaction.

A mismatched linked record fails and remains linked. Do not replace it.

**EARS — integration:**

> WHEN reservation is repeated for one collection item, THE application SHALL return the same optimization-run and experiment IDs.

**EARS — integration:**

> WHEN a linked runtime record does not match the declared request, THE application SHALL fail without replacing the link.

Do not add a separate concurrency test. The short row lock is the concurrency guard.

### F5 + F6 + F7 — ordered Pilot candidate cutover — complete

Replace `candidate_grid` with one ordered `candidates` array. Each candidate contains a stable ID, plan count per side, and attacks per plan.

A recommendation exposes the candidate ID and exact counts. Declared position remains internal and supplies only the last tie-break.

**Implementation hints:**

- Delete `CandidateGrid` and its schemas, fixtures, branches, and tests.
- Generate work by enumerating the ordered candidates.
- Carry candidate ID through mapped work and compute requests.
- Restore declared order during assembly.
- Reject a returned ID or count that differs from the request.
- Add no grid adapter or dual parser.
- Replace the prototype version-one wire shape in place. Git history preserves the removed form.

**EARS — contract and workflow integration:**

> WHEN a Pilot request declares two ordered candidates, THE Pilot workflow SHALL preserve both IDs, their order, and their exact counts through result read-back.

**EARS — removed-shape check:**

> WHEN a request uses the removed candidate-grid field, THE application SHALL reject it before creating a Gust run.

Retain existing scientific Pilot tests. Do not duplicate them for the new container shape.

### F8 + F9 — collection plan and mapped action — complete

**Internal interfaces:**

```elixir
build_collection_work(execution, phase, definition, replica_position)
run_collection_item(collection_item_id)
```

Planning returns typed work items. Mapped execution accepts one collection-item
identifier and rebuilds the canonical work from the stored revision.

Each typed work item carries its declared position, comparison identity and position, side, graph, strategy, budget, plan position, concrete selection seed, evaluation root, attack count, and replica position.

The builder preserves declared order, uses the first required seeds, creates no candidate Cartesian product, and checks total work before Gust submission.

The action uses F4 reservations and returns only compact IDs and completion counts.

Add only these collection controls:

- maximum items in one phase;
- maximum Gust collection concurrency.

Reuse existing ScatterGather concurrency and evidence limits. Add no combined concurrency cap or Gust × ScatterGather product check.

The runtime-contract gate executes every scientific setting that the study schema accepts and binds a mapped item to its immutable revision. [Evaluation study runtime contract](evaluation-study-runtime-contract-future-work.md) records that gate. At this stage, the lifecycle remained unavailable until the later coordinator and activation slices were complete.

**EARS — unit:**

> WHEN a definition contains ordered comparisons and selection seeds, THE builder SHALL produce ordered side-and-plan work using the first required seeds.

**EARS — unit:**

> WHEN planned work exceeds the phase-item cap, THE builder SHALL reject it before Gust submission.

**EARS — mapped-action integration:**

> WHEN one collection item runs, THE action SHALL return compact linked IDs and completion counts without returning evidence matrices.

F4 already proves retry reuse. Do not repeat it.

### F10 + F11 — measured Pilot runtime evidence

`Simulation.Run` gains a non-negative integer `runtime_us` field.

Measure each trial with `System.monotonic_time(:microsecond)`. Use a private helper. Store only elapsed microseconds, not raw timestamps. Add no clock module, behaviour, or time mock.

Build Pilot runtime evidence from persisted optimization milliseconds and trial microseconds. Convert trial values to floating-point milliseconds at the snapshot boundary. Preserve valid zero-millisecond optimization values.

**EARS — simulation integration:**

> WHEN one simulation trial completes, THE application SHALL persist its non-negative elapsed microseconds.

**EARS — assembler:**

> WHEN completed optimization and simulation records are assembled, THE Pilot snapshot SHALL contain their measured durations, including a valid zero-millisecond plan duration.

**EARS — assembler:**

> WHEN a required runtime value is absent, THE assembler SHALL reject the Pilot snapshot.

### F12 + F13 — Pilot fan-in and snapshot

**Internal interface:**

```elixir
assemble_and_store_pilot_snapshot(phase, collection_items, definition)
```

The fan-in loads complete linked records, restores declared order, builds independent side rows over shared attack columns, adds runtime evidence, and creates one snapshot.

Lock the phase row during snapshot create-and-link. A retry returns the linked snapshot.

**EARS — assembly:**

> WHEN complete persisted evidence is assembled, THE fan-in SHALL create aligned matrices in declared order with measured runtime evidence.

**EARS — incomplete evidence:**

> WHEN one required collection item or experiment result is absent, THE fan-in SHALL reject the snapshot.

**EARS — integration:**

> WHEN fan-in repeats for the same phase, THE application SHALL return the same linked snapshot ID.

Existing snapshot tests cover detailed malformed matrix cases.

### F14 + F15 — real Pilot path and pause

The internal supervised coordinator runs Pilot collection, validates its snapshot, runs Pilot analysis, stores the outcome, enters `awaiting_final`, and stops.

This chunk did not activate `start_study/1`. F22+F23 activated the public lifecycle after the Final path was complete.

A phase failure stores a bounded execution error and enters `failed`. Before acceptance, the task locks and checks the execution. Cancellation wins over a late completion.

**EARS — Pilot DAG integration:**

> WHEN complete collection work succeeds, THE Pilot collection DAG SHALL return one snapshot ID and keep evidence matrices out of Gust task results.

**EARS — coordinator integration:**

> WHEN Pilot analysis returns a recommendation or insufficiency, THE coordinator SHALL store that outcome, enter `awaiting_final`, and stop before Final collection.

Cover the recommendation and insufficiency outcomes with shared Pilot fixtures. Existing Pilot tests prove their scientific calculations.

### F16 + F17 + F18 — Final selection and source binding

**Public interface, activated in F22+F23:** `resume_study/2` with `:recommended` or `{:override_insufficient, candidate_id}`.

The resume transaction locks the paused execution, validates the tagged selection, resolves one declared candidate, freezes its counts, stores `pilot_override`, enters `collecting_final`, and creates the Final phase row. F19+F20+F21 start the real Final coordinator after the resume transaction commits. F16+F17+F18 add no coordinator shell or no-op task.

One `Final.Binding.verify/2` function checks the frozen source at every Final boundary.

**EARS — command integration:**

> WHEN a recommended or insufficient Pilot is resumed with its permitted selection form, THE application SHALL freeze one declared candidate, set the correct override marker, and enter Final collection.

Cover both valid resume forms with shared setup.

**EARS — command integration:**

> WHEN resume uses the wrong selection form or an undeclared candidate, THE application SHALL return a bounded error and leave the execution at `awaiting_final`.

**EARS — binding unit:**

> WHEN Final input differs from the frozen candidate, counts, family, or Pilot source, THE shared binding SHALL reject it.

Use a small fixture-backed mismatch table. Do not repeat it at each caller.

### F19 + F20 + F21 — complete Final path and result — complete

The Final coordinator builds fresh Final work, uses Final seeds and roots, rejects Pilot evidence and runtime IDs, creates one Final snapshot, runs complete-family analysis, stores one compact result, enters `succeeded`, and stops.

The result row is unique by execution. It stores accepted phase references, Pilot outcome, selected candidate, override marker, compact Final family, reproduction assertions, optional timing, and insertion time. It stores no evidence matrix.

**EARS — Final collection integration:**

> WHEN Final collection runs, THE application SHALL use the frozen counts and separate Final seeds and SHALL not reuse any Pilot evidence or runtime ID.

**EARS — Final coordinator integration:**

> WHEN Final analysis returns one complete family, THE coordinator SHALL store one compact result and change the execution to `succeeded`.

This coverage also checks result persistence and read-back. Existing Final tests cover complete-family validation details.

### F22 + F23 — public lifecycle activation — complete

The six public study functions are active. The direct Pilot and Final facade groups are removed.

**EARS — backend journey:**

> WHEN a valid study produces a recommended Pilot, THE public API SHALL pause, resume with `:recommended`, complete Final analysis, and return one compact result with `pilot_override: false`.

**EARS — backend journey:**

> WHEN a valid study produces an insufficient Pilot, THE public API SHALL pause, resume only with `{:override_insufficient, candidate_id}`, complete Final analysis, and return one compact result with `pilot_override: true`.

These are the only automated full core journeys.

**Manual check:** create a revision, start an execution, inspect paused status, resume it, and inspect the result and four Gust runs.

## Slice 4 — timing

### T1 + T2 — replica schedule and elapsed intervals — complete

For each tier, run warm-up replica `-1`, then measured replicas `0` through `4`. Run tiers sequentially. Do not start measured work until the warm-up succeeds.

Measure with `System.monotonic_time(:microsecond)` in the Final coordinator VM:

- plan selection: first optimization dispatch to last optimization completion;
- simulation: first experiment dispatch to last experiment completion;
- total: first optimization dispatch to last experiment completion.

The intervals include Gust and ScatterGather wait time. Plan-selection and simulation intervals can overlap. Measure total directly; do not add the other intervals.

The small interval function can accept an optional `now_us` function for its unit test. Add no clock module or behaviour.

**EARS — unit:**

> WHEN Final timing work is planned for one tier, THE planner SHALL place one warm-up before measured replicas zero through four.

**EARS — unit:**

> WHEN plan selection and simulation spans overlap, THE recorder SHALL calculate each elapsed span and total from its own boundaries.

### T3 + T4 — environment, equivalence, and canonical evidence — complete

Read the current measured-environment revision from application configuration. Compare it with the definition before the warm-up and before and after each measured replica. A missing or changed value fails with a bounded error.

Create one typed non-timing summary for each measured replica. Compare summaries directly. Add no content hash.

After all five summaries match, replica `0` supplies Final evidence. Replicas `1` through `4` supply timing variation only. Warm-up data supplies neither timing nor outcome evidence.

Do not retry a rejected replica.

**EARS — unit:**

> WHEN five measured replicas have equal non-timing summaries, THE gate SHALL accept them and select replica zero.

**EARS — unit:**

> WHEN one measured replica has a different non-timing summary, THE gate SHALL reject the measured set.

Use one representative difference.

**EARS — unit:**

> WHEN the configured environment assertion changes before or after a replica, THE gate SHALL return a bounded failure.

### T5 — timing summary and manual journey — next

Store microseconds explicitly. For each tier and duration type, keep the five measured values, median, minimum, and maximum.

**Internal interface:**

```elixir
@spec summarize([ReplicaTiming.t()]) ::
        {:ok, TierTiming.t()} | {:error, StudyError.t()}
```

Require exactly measured replicas `0` through `4`.

**EARS — unit:**

> WHEN five measured replica durations are supplied, THE summary SHALL report their values, median, minimum, and maximum for each duration type.

Use one unsorted five-value example.

**Manual timed journey:** run one tiny controlled study. Check the warm-up, five measured replicas, replica-zero evidence, timing summary, and successful result. Do not assert exact durations and do not collect real study evidence.

## Acceptance gates

### Revision and lifecycle model

Accept Slice 2 when:

- valid revisions store once;
- unresolved graphs store nothing;
- lifecycle transitions are explicit;
- execution and phase uniqueness constraints pass.

### Core outcome path

Accept Slice 3 when:

- every optimization run has a concrete seed;
- collection retries reuse linked runtime and snapshot records;
- Pilot and Final evidence remain separate;
- both public journeys pass;
- one Holm correction covers the complete Final family;
- Gust state contains compact IDs rather than evidence matrices.

### Timing

Accept Slice 4 when:

- pure schedule, interval, equivalence, environment, and summary tests pass;
- the manual timed journey passes;
- the compact result reports all required timing data.

## Final checks

After each slice, run focused tests and the nearest existing regressions. Before a commit, run the normal repository hook against a fresh disposable test database.

Stop before deployment or real evidence collection. Report unresolved scientific or resource decisions instead of choosing defaults.
