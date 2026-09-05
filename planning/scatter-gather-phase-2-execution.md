# Phase 2 Execution

## Scope

Complete local ScatterGather simulation execution. Preserve public results, progress, PubSub payloads, and report behavior. Replace batch checkpoints and partial-trial resume with atomic completion.

Tests cover behavior and persisted state. Do not add or change tests that assert telemetry events, metrics, spans, traces, or logs.

## Chunk 1: Local Executor

Add a common `NetworkDefense.Compute.ScatterGather.Executor` behaviour. Add `NetworkDefense.Compute.LocalExecutor` against the executor behaviour, existing operation contract, and telemetry helper.

Use the task supervisor and process propagator defined in the design. Limit concurrency, preserve keyed unordered results, report weighted progress, cancel active work after a failure, and skip gather after a partition failure.

Add behavioral tests for success, empty input, task exit, operation error, gather error, weighted progress, callback failure, and concurrency. Do not inspect observability output.

## Chunk 2: Atomic Experiment Lifecycle

Add `Experiments.start_empty/1` and `Experiments.complete_with_runs/3`.

Lock lifecycle changes. Express valid and invalid states with pattern-matched private clauses. Reject partial experiments by their `completed_trials` state. Insert all runs and iteration steps and complete the experiment in one transaction. Reuse the existing insert chunking helpers. Use changesets only to construct state updates.

Add transaction and lifecycle tests for empty running, empty failed, completed, cancelled, partial, successful completion, count mismatch, and rollback.

## Chunk 3: Simulation Operation

Add `NetworkDefense.Compute.SimulationOperation`.

Scatter an empty experiment into weighted trial ranges. Load and materialize each partition's inputs. Run trials sequentially within a partition. Gather unordered results through atomic completion.

Add behavioral tests for partition shape, completed-trial rejection, execution results, and gather persistence. Do not inspect spans, events, metrics, or logs.

## Chunk 4: Context And Worker Migration

Add `Simulations.run/2`. Compose caller progress with optional dashboard events. Convert internal exceptions to the existing public error contract. Keep failure ownership in `Simulations`.

Migrate `SimulationWorker` to `Simulations.run/2`. Preserve completed, failed, and progress PubSub payloads. Cover public results, state changes, and payloads with behavioral tests.

## Chunk 5: Shared Helpers And Evaluation

Move shared simulation setup helpers to `Simulator`. Update optimization callers without moving optimization to ScatterGather.

Migrate evaluation to `Simulations.run/2`. Preserve global weighted progress and completed-experiment resume. Remove partial-trial resume calculations. Test evaluation behavior and progress payloads.

## Chunk 6: Remove Old Paths

After all callers migrate, delete `run_or_resume/2`, `run_batches/4`, batch concurrency code, obsolete experiment batch APIs, and the temporary batch-completion telemetry helper.

Use source review to confirm that `Simulations` has no direct task-stream, batch-persistence, Logger, or Tracer code. Update tests that call removed APIs, but do not replace them with observability tests.

## Verification

After each chunk, compile with warnings as errors and run the affected behavioral tests. After all chunks, launch the application and query health, readiness, metrics, trace, and log endpoints. Confirm the ScatterGather and simulation signals through those endpoints only. Run formatting and the project precommit gate before completion.
