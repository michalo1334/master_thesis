# Phase 1 Execution

## Chunk 1: Generic Interface And Telemetry

Add:

- `src/lib/network_defense/compute/scatter_gather.ex`
- `src/lib/network_defense/compute/telemetry.ex`
- a behavior-contract test for `ScatterGather`

Update the central metric list with bounded ScatterGather run and partition metrics.

Implement the callback and observability contracts from the design files. Do not add `LocalExecutor` or `SimulationOperation`. Reuse `NetworkDefense.Observability.duration_ms/1`.

## Chunk 2: Simulation Telemetry Extraction

Add:

- `src/lib/network_defense/simulation/telemetry.ex`

Update:

- `src/lib/network_defense/simulations.ex`
- `src/lib/network_defense/simulation/simulation_report.ex`
- affected behavioral tests

Move simulation run, compute, report, enqueue-failure, and current batch-completion tracing or logging into the helper. Keep persistence, PubSub, and progress in their current owners. Preserve current public function signatures and behavior.

Do not change the worker, evaluator, experiment lifecycle, optimization callers, batch persistence, partial resume, or simulation execution strategy. Do not add any Phase 2 API.

## Verification

After each chunk, compile with warnings as errors. After both chunks, launch the application and query the relevant runtime endpoints (telemetry, logs, metrics) to confirm the expected output. Do not write or run telemetry, log, or metrics tests. Run formatting and the project precommit gate before completion.
