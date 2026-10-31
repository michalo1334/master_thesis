# Evaluation study pipeline refactor plan

> Historical legacy refactor record. Its R7 checkpoint and pending R8/R9 sequence describe the old delivery, rather than current native status.
> Use the [current pipeline guide](evaluation-study-pipeline.md), [operator guide](../evaluation2.md) and [verification record](../history/evaluation2-verification.md).
> Code examples below illustrate superseded contracts and are not executable native guidance.

## Status

Implemented through R7 on the modular study-pipeline branch.

R8 manual end-to-end verification is the next behavioral gate. R9 automated test reconstruction remains future work. This plan is now an implementation record. The [current pipeline design](evaluation-study-pipeline.md) is the architecture authority.

## Purpose

Rebuild the evaluation study pipeline as a readable Gust DAG architecture. Organize the code by lifecycle stage. Make high-level stages and low-level Gust tasks explicit. Reduce total production code where possible.

This is a destructive rebuild. The refactor does not preserve internal modules, database shapes, Gust payload shapes, or lower-level workflow interfaces.

## Authority and reference baseline

Use these Git revisions as read-only references:

- implementation and test reference: `b50e5bbb6ddb5a2425815355bc00143ce6f76147`;
- pre-refactor tree reference: `be1f96196a23928c3d1d01974f9fc8b8a74d0b64`.

Do not copy the old architecture by default. Use the baseline to recover scientific rules, failure cases, and test scenarios after the new design is complete.

## Preserved contracts

The rebuild preserves only these contracts.

### Scientific method

Preserve:

- separate Pilot collection and Pilot analysis;
- an explicit pause before Final work;
- explicit resume with a frozen Final candidate;
- separate Final collection and Final analysis;
- sequential Final tiers;
- one excluded warm-up for each tier;
- five measured replicas for each tier;
- complete-family equality before the Final snapshot;
- replica-zero evidence as the accepted Final snapshot;
- one family correction during Final analysis;
- compact successful study results.

The environment policy changes to shared work boundaries. One environment check can serve as the end boundary of one replica and the start boundary of the next replica.

### Public study API

Preserve the public operations and their purpose:

- create a study revision;
- start a study;
- read study status;
- resume a paused study;
- cancel a study;
- read a successful result.

The public facade remains stable. Internal modules and persistence can change.

## Contracts that can change

The rebuild can replace:

- all internal Study, Pilot, and Final module names;
- all internal function signatures;
- all Gust task payloads;
- all Gust action modules;
- all workflow wrappers;
- all database tables and migrations used only by the study pipeline;
- all lower-level comparison, family, optimization, simulation, and evidence interfaces;
- all current automated Study, Pilot, and Final tests.

Any change must still preserve the scientific method and public study API.

## Destructive cutover policy

1. Delete replaced implementation code instead of adding compatibility delegates.
2. Delete affected automated tests instead of updating them during the rebuild.
3. Add no dual reader, fallback, adapter, or deprecated namespace.
4. Allow incomplete intermediate branches while a stage is under construction.
5. Complete one target stage before work starts on the next target stage.
6. Use the baseline commits to recover old scenarios only after the full pipeline works manually.

The worktree contains unrelated user changes. The rebuild must not modify or restore those files.

## Target architecture

```text
NetworkDefense.Evaluation.Study
├── Start
├── Resume
├── Cancel
├── Status
├── Results
├── Revisions
├── Definition...
└── Pipeline
    ├── Coordinator
    ├── Runner
    ├── Lifecycle
    ├── ExecutionAccess
    ├── State
    ├── Failure
    ├── GustAdapter
    ├── GustCallback
    ├── GustNotifier
    ├── GustWaiter
    ├── WaitDeadline
    ├── Collection
    │   ├── Planner
    │   ├── Runner
    │   ├── ItemStore
    │   ├── Reservations
    │   ├── ConcurrencyGate
    │   ├── WorkItem
    │   └── Receipt
    ├── Pilot
    │   ├── Error
    │   ├── Limits
    │   ├── Collection
    │   └── Analysis
    ├── Final
    │   ├── Error
    │   ├── Limits
    │   ├── Collection
    │   └── Analysis
    └── Result
```

## Elixir design examples

The plan keeps substantial Elixir examples in separate files:

- [coordinator and runner](examples/evaluation-study-pipeline-refactor/pipeline_runner.ex);
- [stage IO families](examples/evaluation-study-pipeline-refactor/stage_io.ex);
- [Gust adapter and completion callback](examples/evaluation-study-pipeline-refactor/gust_adapter.ex);
- [Pilot Collection task](examples/evaluation-study-pipeline-refactor/pilot_collection_prepare.ex);
- [Pilot Collection DAG](examples/evaluation-study-pipeline-refactor/pilot_collection_dag.exs);
- [Final Collection DAG](examples/evaluation-study-pipeline-refactor/final_collection_dag.exs);
- [measured-replica DAG macro](examples/evaluation-study-pipeline-refactor/measured_replica_dag.ex);
- [provisional persistence schemas](examples/evaluation-study-pipeline-refactor/persistence.ex).

These examples are design references. They are not production modules. The example formatter keeps the native Gust `task_action` style.

The examples must pass:

- Elixir parsing;
- `mix format --check-formatted` with the example formatter;
- the project's strict Credo configuration.

## Execution ownership

### Coordinator

`Study.Pipeline.Coordinator` owns process concerns only:

- start one supervised process;
- register the execution process;
- perform the caller handshake;
- call the pipeline runner;
- terminate normally after pause, completion, cancellation, or bounded failure.

The coordinator does not own phase-specific database transitions.

### Runner

`Study.Pipeline.Runner` selects the active stage.

```text
Pilot start
  → Pilot.Collection
  → Pilot.Analysis
  → paused

Final resume
  → Final.Collection
  → Final.Analysis
  → completed
```

The current stage owns its successful transition. The failure module owns failure persistence.

The Final collection stage runs in the coordinator process. Timing messages can continue to target the registered process.

### Elixir reference

See [the coordinator and runner example](examples/evaluation-study-pipeline-refactor/pipeline_runner.ex).

The example keeps process ownership in `Coordinator` and stage composition in `Runner`. Each stage performs its own successful transition.

## Stage IO model

Do not create separate Input and Output contracts for each task.

Each stage owns one IO family. Low-level tasks accept and return values from that family.

### Stage return rules

- Pilot Collection returns `Pilot.Analysis.IO`.
- Pilot Analysis returns a paused result.
- Final Collection returns `Final.Analysis.IO`.
- Final Analysis returns a completed result.

Persisted state remains authoritative after pause and completion.

### Stage handoff reference

The [coordinator and runner example](examples/evaluation-study-pipeline-refactor/pipeline_runner.ex) shows the intended handoff:

- a collection stage returns the next analysis IO;
- Pilot Analysis returns `:paused`;
- Final Analysis returns `:completed`.

### Pilot Collection IO

The phase IO contains loaded domain values for the active execution, phase, definition, planned work, collection items, Gust run, and snapshot.

A nested item IO represents one mapped collection item. Gust persists only compact stable references.

See [the stage IO example](examples/evaluation-study-pipeline-refactor/stage_io.ex) for the Pilot and Final IO families.

The IO loader creates a complete domain value from an execution or Gust run. The loader can reject an invalid stage before task work starts.

### Pilot Analysis IO

The phase IO contains the accepted Pilot snapshot, analysis request, Gust run, candidate work, result, and lifecycle outcome.

A nested candidate item represents one mapped candidate-comparison calculation.

### Final Collection IO

Use scoped types owned by the phase:

- phase IO for the complete Final collection;
- tier IO for one sequential tier;
- replica IO for one warm-up or measured replica;
- item IO for one mapped plan or simulation item.

This avoids one flat struct with many optional fields. The [stage IO example](examples/evaluation-study-pipeline-refactor/stage_io.ex) shows the scoped structs and types.

A plan task accepts `IO.Item`, while tier orchestration accepts `IO.Tier`.

### Final Analysis IO

The phase IO contains the accepted Final snapshot, request, Gust run, complete comparison family, corrected result, and compact pipeline result.

A nested comparison item represents one mapped Final-family member.

## Gust integration

### Adapter macro

`Study.Pipeline.GustAdapter` implements the common Gust action boundary:

1. decode Gust arguments and context into stage IO;
2. call the task's domain function;
3. encode the returned IO into a compact Gust result;
4. convert bounded domain failures into permanent Gust failures;
5. leave unexpected failures retryable.

Each low-level task owns a nested `Gust` module with explicit decode and encode functions.

The central DAG uses Gust's native `task_action` declarations. Add all used `task_action` arities to the formatter's no-parentheses list.

### Elixir references

See:

- [the shared Gust adapter and callback example](examples/evaluation-study-pipeline-refactor/gust_adapter.ex);
- [the Pilot Collection task example](examples/evaluation-study-pipeline-refactor/pilot_collection_prepare.ex).

The adapter macro standardizes transport behavior. It does not create graph edges or rescue unexpected exceptions. The domain task works with loaded values. Its nested Gust module owns compact persisted payloads.

### Completion callback

`Study.Pipeline.GustCallback` defines the shared non-authoritative completion callback.

The callback sends only the Gust run ID. Persisted Gust state remains authoritative.

See [the shared Gust adapter and callback example](examples/evaluation-study-pipeline-refactor/gust_adapter.ex).

A callback failure cannot change the Gust run result. The waiter reloads the persisted run before it accepts completion.

Each checked-in DAG file must still contain a direct `use Gust.DSL` declaration because the Gust loader inspects the file syntax.

## DAG ownership

Each stage owns one central DAG. The central DAG shows stage order and dependency edges.

Low-level task modules own behavior and Gust codecs. They do not own cross-task order.

### Pilot Collection

```text
prepare collection
→ mapped collection items
→ assemble Pilot snapshot
```

See [the Pilot Collection DAG example](examples/evaluation-study-pipeline-refactor/pilot_collection_dag.exs).

The example keeps every dependency edge in one checked-in DAG. Its native `task_action` syntax requires formatter entries for the used arities.

### Pilot Analysis

```text
prepare candidates
→ mapped candidate comparisons
→ select Pilot outcome
```

### Final Collection tier

```text
initial environment boundary
→ warm-up
→ first measured boundary
→ measured replica 0
→ shared boundary
→ measured replica 1
→ shared boundary
→ measured replica 2
→ shared boundary
→ measured replica 3
→ shared boundary
→ measured replica 4
→ final environment boundary
→ complete tier
```

The measured replica subgraph remains static. A compile-time macro emits the repeated named tasks for positions zero through four.

The phase DAG shows the five replica declarations. The measured-replica module shows the internal task order once.

### Elixir references

See:

- [the Final Collection DAG example](examples/evaluation-study-pipeline-refactor/final_collection_dag.exs);
- [the measured-replica macro example](examples/evaluation-study-pipeline-refactor/measured_replica_dag.ex).

The central DAG shows every shared environment boundary. The macro creates named static tasks and supplies bounded replica positions and timing events to the task adapters.

### Final Analysis

```text
prepare Final family
→ mapped family members
→ correct complete family
```

## Environment boundary policy

The old DAG used separate checks after one measured replica and before the next measured replica.

The new DAG uses one shared boundary check between adjacent replicas. This check serves both purposes.

The policy requires checks:

- before warm-up;
- between warm-up and the first measured replica;
- between each pair of measured replicas;
- after the final measured replica.

This policy brackets every work interval and removes duplicate adjacent tasks.

The check compares the declared environment identity at the boundary. It is not continuous environment monitoring.

## Contract and schema policy

Domain modules exchange typed values. Do not validate typed internal values with JSON Schema.

Use schema or codec validation only when serialized data crosses a trust boundary, such as:

- public JSON input;
- an external computation response;
- a generic persisted document that is decoded into a domain value.

Split mixed validators during stage construction. Remove internal validation paths when stage IO and codecs make them redundant.

Remove the Pilot and Final Wire modules. Place serialization in the boundary that uses it.

## Persistence redesign

The old database model is not a compatibility contract.

Design the new model after the stage IO types are defined. Keep only records that support public lifecycle operations, restart inspection, stable effects, and result retrieval.

The target concepts are:

- immutable study revision;
- study execution and public lifecycle state;
- one record for each stage attempt;
- one or more Gust run bindings for a stage;
- stable collection work items;
- one compact successful result.

The implementation can replace old tables and migrations. No data migration is required for the prototype.

Do not persist complete in-memory IO structs. Persist stable identifiers, accepted references, bounded errors, and compact results.

### Elixir reference

See [the provisional persistence example](examples/evaluation-study-pipeline-refactor/persistence.ex).

The example separates stage attempts from ordered Gust run bindings. The final fields depend on the completed stage IO design. Stable collection work remains separate because retries must reuse the same external effects.

## Stage ownership

### Shared Collection

`Study.Pipeline.Collection` owns logic used by Pilot and Final collection:

- work planning;
- tier filtering;
- stable item storage;
- reservation and reuse of effects;
- optimization and simulation execution;
- collection receipts;
- collection concurrency.

Move the current behavior first. Split planning, execution, storage, and reservation responsibilities after the namespace is stable.

### Pilot Collection

Owns:

- the Pilot collection DAG;
- prepare, collect, and assemble tasks;
- Pilot snapshot construction;
- snapshot contracts;
- snapshot validation at serialized boundaries;
- collection-stage transition to Pilot analysis.

### Pilot Analysis

Owns:

- candidate preparation;
- candidate-comparison calculation;
- Pilot selection;
- Pilot request and result contracts;
- Pilot analysis client and external codecs;
- Pilot lifecycle outcome;
- transition to the public pause state.

Pilot-level error and limit types are shared by Pilot Collection and Pilot Analysis.

### Final Collection

Owns:

- sequential tier orchestration;
- the static tier DAG;
- warm-up and measured replica preparation;
- environment boundaries;
- timing boundaries and interval summaries;
- complete-family replica equality;
- replica-zero snapshot construction;
- snapshot contracts;
- transition to Final analysis.

### Final Analysis

Owns:

- Final request construction and source binding;
- family member calculation;
- complete-family correction;
- Final result contracts and external codecs;
- compact pipeline result creation;
- transition to completed.

Final-level error and limit types are shared by Final Collection and Final Analysis.

### Pipeline Result

`Study.Pipeline.Result` owns the compact successful result because the result represents the complete study, not only Final analysis.

The public result operation reads this value.

## Destructive implementation slices

### R0 — Record the baseline and delete obsolete tests

- Record both baseline Git revisions in the working notes.
- Delete automated tests for the replaced Study, Pilot, and Final implementation.
- Delete obsolete test support modules that only serve those suites.
- Keep lower-level tests only until their implementation is replaced.
- Make no attempt to keep the test environment green during the rebuild.

Exit condition: the old tests remain recoverable from Git and no stale pipeline test is treated as current authority.

### R1 — Create the pipeline foundation

- Create the Pipeline namespace.
- Add Coordinator, Runner, State, ExecutionAccess, Lifecycle, Failure, GustAdapter, and GustCallback.
- Add formatter support for native Gust DSL calls.
- Define stage result conventions.
- Define the initial persistence model and destructive migrations.

Exit condition: the application compiles with a minimal pipeline shell, even if no study stage runs yet.

### R2 — Rebuild shared Collection

- Move collection behavior into `Pipeline.Collection`.
- Separate planning, execution, item storage, reservations, and concurrency.
- Define shared work-item and receipt domain types.
- Remove replaced Study Collection modules.

Exit condition: Pilot and Final stage code can use one collection API without legacy namespaces.

### R3 — Rebuild Pilot Collection

- Define Pilot Collection IO and item IO.
- Move snapshot contracts under Pilot Collection.
- Implement prepare, collect, and assemble domain tasks.
- Implement nested Gust adapters.
- Implement the central Pilot collection DAG.
- Implement snapshot acceptance and transition to Pilot analysis.
- Delete replaced Pilot collection modules and DAG code.

Exit condition: Pilot Collection can produce `Pilot.Analysis.IO` from a valid execution.

### R4 — Rebuild Pilot Analysis

- Define Pilot Analysis IO and candidate item IO.
- Move Pilot contracts and scientific computation under the stage.
- Split boundary validation from internal domain logic.
- Remove Pilot Wire.
- Implement prepare, evaluate, and select tasks and adapters.
- Implement the central Pilot analysis DAG.
- Persist the accepted outcome and enter the pause state.
- Delete the old Pilot namespace.

Exit condition: a study can start, complete Pilot work, and pause.

### R5 — Rebuild Final Collection

- Define phase, tier, replica, and item IO types.
- Implement sequential tier orchestration.
- Implement environment boundary checks.
- Implement warm-up and measured replica tasks.
- Implement timing boundaries and summaries.
- Implement the compile-time measured-replica subgraph.
- Implement complete-family equality and replica-zero snapshot creation.
- Implement transition to Final analysis.
- Delete replaced Final collection and Timing modules.

Exit condition: a resumed study can produce `Final.Analysis.IO`.

### R6 — Rebuild Final Analysis

- Define Final Analysis IO and comparison item IO.
- Move Final contracts and computation under the stage.
- Split boundary validation from internal domain logic.
- Remove Final Wire.
- Implement prepare, compare, and correct tasks and adapters.
- Implement the central Final analysis DAG.
- Create the compact pipeline result.
- Enter the completed state.
- Delete the old Final namespace.

Exit condition: a resumed study can complete and store a compact result.

### R7 — Connect the public facade

- Connect the preserved public study operations to the new persistence and pipeline modules.
- Rebuild status, resume, cancellation, and result read paths.
- Remove all remaining old pipeline modules, tables, migrations, DAGs, and support code.
- Update the design documents to describe only the new architecture.

Exit condition: no production reference uses an old Study, Pilot, or Final pipeline module.

### R8 — Manual end-to-end verification

Run one complete manual study journey:

1. create a study revision;
2. start the study;
3. complete Pilot collection and analysis;
4. confirm the public pause state;
5. resume with an accepted candidate;
6. complete sequential Final tiers;
7. complete Final analysis;
8. read the compact result;
9. inspect Gust runs, stage records, collection items, environment boundaries, and timing summaries.

Also run one cancellation journey during active work.

Exit condition: the public API completes the scientific method and produces inspectable persisted evidence.

### R9 — Rebuild automated tests later

This slice is outside the immediate destructive rebuild.

Use the baseline commit to recover scenarios. Rewrite tests against the new architecture. Do not restore old internal assertions unchanged.

Prioritize:

- public lifecycle journeys;
- scientific calculations;
- stage IO codecs;
- persistence uniqueness and stable effects;
- exact static DAG topology;
- cancellation and bounded failure behavior;
- environment boundaries;
- timing summaries;
- compact result construction.

## Verification policy during the rebuild

Do not run or repair the deleted automated pipeline tests during R0 through R7.

At completed slice boundaries:

- format changed source;
- compile the application when the slice reaches a coherent state;
- inspect generated Gust DAG definitions where applicable;
- inspect database migrations and schemas where applicable.

The first complete behavioral gate is the manual end-to-end journey in R8.

Automated verification resumes in R9.

## Stop conditions

Stop and return to design review if:

- a proposed simplification changes the preserved scientific method;
- a public study operation requires a signature change;
- the new persistence model cannot represent pause, resume, cancellation, stable collection effects, or multiple Final tier runs;
- a Gust limitation prevents the required static graph;
- the final production code grows without a clear ownership or correctness benefit.

## Review questions

Before implementation, approve or revise:

1. the destructive scope;
2. the target module tree;
3. the stage IO model;
4. the shared environment boundary policy;
5. the persistence redesign freedom;
6. the deletion and delayed-reconstruction test policy;
7. the slice order.
