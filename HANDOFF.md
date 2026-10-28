# Next-agent handoff: modular study pipeline

## Current status

The evaluation study pipeline refactor is complete through R7.

The current branch is `refactor/modular-study-pipeline`. R7 production and documentation changes are committed on the branch. Use the current `HEAD` as the source checkpoint.

R8 manual end-to-end verification is the next behavioral gate. R9 automated test reconstruction remains future work.

## Worktree safety

The worktree also contains unrelated user edits and deletions. Preserve them. In particular, do not restore deleted thesis, in-progress, agent, or tooling documents from Git history or the index.

Local `.pi/tmp` files include manual-journey artifacts and recovery records. Review them separately before staging.

## Authority

Read these files before further study-pipeline work:

1. [Current pipeline design](docs/design/evaluation-study-pipeline.md)
2. [Modular refactor plan](docs/design/evaluation-study-pipeline-refactor-plan.md)
3. [Evaluation architecture](docs/architecture/evaluation-architecture.md)
4. [Scientific methodology](docs/concepts/evaluation-methodology.md)
5. [Requirements](docs/concepts/requirements.md)
6. [Vocabulary](docs/concepts/vocabulary.md)
7. [Decision history](docs/history/evaluation-decisions.md)
8. [Deferred runtime contract](docs/design/evaluation-study-runtime-contract-future-work.md)

The current design document defines the architecture. The refactor plan records the destructive migration and the remaining R8 and R9 work.

## Implemented architecture

The public `NetworkDefense.Evaluations` facade keeps six study operations:

- create a study revision;
- start a study;
- read study status;
- resume a paused study;
- cancel a study; and
- read a successful result.

The internal pipeline has these boundaries:

- `Pipeline.Collection` owns shared planning, stable items, reservations, concurrency, receipts, and evidence assembly.
- `Pipeline.Pilot.Collection` owns Pilot collection IO, Gust adapters, snapshot contracts, and acceptance.
- `Pipeline.Pilot.Analysis` owns candidate IO, computation, Gust adapters, outcome persistence, and the pause transition.
- `Pipeline.Final.Collection` owns sequential tiers, static replica topology, environment boundaries, timing, replica-family validation, snapshot acceptance, and the versioned Final Analysis handoff.
- `Pipeline.Final.Analysis` owns request binding, family computation, Gust orchestration, restart-safe run reuse, and completion.
- `Pipeline.Result.Store` owns compact-result persistence and validated read-back.

Final Collection uses one excluded warm-up at position `-1` and five measured replicas at positions `0..4`. Its static DAG has one environment check before warm-up, one before replica `0`, one shared check between each adjacent measured replica, and one after replica `4`.

The Final Collection phase keeps its scalar Gust run ID empty. Ordered `StudyPhaseRun` rows hold one run per declared tier. The other three stages use scalar run IDs.

## Prototype limits

Preserve these boundaries:

- no deployment or real evidence collection;
- no automatic coordinator recovery;
- no phase replay;
- no replacement replicas;
- no dynamic DAG generation;
- no new scientific defaults;
- no Pilot or Final public facade groups; and
- no exactly-once computation claim.

Gust callbacks are wake-up signals. Persisted Gust status remains authoritative. Stable collection items make repeated effects safe within the prototype contract.

## Verification record

The current `HEAD` passed:

- formatting;
- warnings-as-errors compilation in development and test environments;
- strict Credo;
- project test-environment Dialyzer;
- all six Gust DAG loads;
- legacy-namespace searches; and
- the commit-hook test suite with 638 passed and two excluded.

Dialyzer skipped the one documented external Gust type warning.

## Next actions

1. Run R8 manual end-to-end verification:
   - complete one public study through Pilot pause, Final resume, sequential tiers, Final Analysis, and result read-back;
   - inspect phase rows, tier runs, collection items, environment boundaries, timing summaries, and Gust runs; and
   - run one cancellation journey during active work.
2. Rebuild automated study tests in R9 from the pre-refactor baseline. Test public behavior and current contracts. Do not restore old internal assertions unchanged.

Require a separate approved plan for deployment, real evidence collection, automatic recovery, replay, replacement replicas, or UI expansion.
