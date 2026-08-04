# Phase 2 Implementation Plan

## Outcome

Canonical segment-policy graphs drive a deterministic in-memory host-to-service reachability projection. Simulation and optimization consume the projection. The network canvas displays it without allowing operational-edge edits.

## Shared Context

Before implementation, create `/tmp/opencode/reachability-phase2-context.md`. Every subagent reads it before editing. It records:

- `NetworkReachability` is an in-memory marker only. It must never be saved or included in canonical graph contracts.
- A policy matches when protocol is `any` or equals the target service protocol, and its port range is absent or contains the target port.
- Rules are directed, deny by default, compose by OR, and require an explicit self-rule for same-segment traffic.
- Every effective `{source host, target service}` pair produces one stable operational edge ID derived from graph ID and both endpoint IDs.
- Preserve unrelated local work, including the uncommitted simulation batch-size change.

## Chunk 1: Materializer

Assign `implementor_fast` to add `NetworkDefense.Graph.MaterializeReachability` and its focused tests.

1. Materialize a graph containing canonical topology plus `NetworkReachability` marker edges.
2. Resolve `Contains`, `Runs`, and `SegmentReachability` only in this module.
3. Sort inputs and derive UUID-compatible operational IDs deterministically from graph ID, source host ID, and target service ID.
4. Remove any existing marker edges before adding the effective flow set so repeated materialization is idempotent.
5. Keep canonical nodes and edges unchanged.

Test directed matching, deny-by-default, same-segment self-rules, protocol and port-range matching, duplicate policy deduplication, deterministic ordering and IDs, and idempotence.

## Chunk 2: Generated Topology

Assign `implementor_fast` to replace direct flow generation in `EnterpriseTopology`.

1. Replace `add_reachability/3` and its host/service pair helpers with a segment-policy table.
2. Keep `@transitions`; it selects generated host roles and is not reachability policy.
3. Produce equivalent policies for ingress HTTPS, DMZ API access, internal PostgreSQL access, workstation LDAP/SMB access, and management SSH access.
4. Update the characterization-flow test to materialize before checking the existing effective flow set.

The seeded `hosts: 8, seed: 7` topology must still produce 13 effective operational flows.

## Chunk 3: Simulation Boundaries

Assign `implementor_fast` to update the two simulator entry points.

1. Materialize once before `Simulator.run_batch/5` in `NetworkDefense.Simulations`.
2. Materialize before `Simulator.run_experiment/3` in `SimulationObjective.expected_blast_radius/2`.
3. Keep `RemoteServiceExploitation` and `ReuseCredentialRule` unchanged. Both already traverse marker edges and no longer filter by protocol or port.
4. Update simulation and optimization tests to pass canonical graphs through the boundary.
5. Update baseline graph normalization so graph identity is stable before materialization. Derived IDs include the graph ID.

The seeded blast-radius distribution remains `%{1 => 42, 2 => 54, 3 => 73, 4 => 31}` with mean `2.465`.

## Chunk 4: Projection API

Assign `implementor_fast` to add a read-only dashboard projection operation.

1. Add typed payload and reply contracts under `src/lib/network_defense_web/contracts/dashboard/graph/`.
2. Accept a graph revision ID and return the saved revision's segments, hosts, policy links, and derived operational flows by ID.
3. Load the canonical revision, materialize in memory, and serialize only the projection response. Do not route marker edges through canonical graph contracts.
4. Add the LiveView handler and dashboard contract tests.
5. Regenerate TypeScript contracts with `mix gen.contracts`.

The operation has no mutation path and no projection data is persisted.

## Chunk 5: Network View

Assign `implementor_fast` to implement all frontend edits. Pass the shared context and the generated projection-contract shape in its prompt.

1. Add `fetchGraphProjection(graphRevisionId)` to `dashboard-api.ts` and its tests.
2. Update `NetworkCanvasProjection.ts` to combine canonical topology with server-derived flows.
3. Fetch only for a saved, clean document. Mark the network layer stale while `document.isDirty`, then refresh it after a successful save.
4. Retain selectable segment-policy links at low zoom.
5. Draw distinct, noninteractive host-to-service operational flows at high zoom. They have accessible labels but cannot be selected, changed, or deleted.
6. Add focused projection, API, and canvas tests.

Do not add operational flows to `EditableGraphDocument` or the editable presentation registry. Do not update `ForceLayout.svelte.ts`: the network view uses explicit graph positions, and it does not route the transient flow layer.

After this chunk, have `svelte-file-editor` validate the changed Svelte files with the Svelte tooling. It reviews only; `implementor_fast` performs the implementation as requested.

## Chunk 6: Benchmark

Assign `implementor_fast` to update `src/priv/bench/map_fun_bench.exs` to construct canonical topology and materialize it before benchmarking. It must not build direct `NetworkReachability` edges.

## Verification

Run focused checks after each chunk, then run:

```bash
mix gen.contracts
mix precommit
```

Confirm repository search finds no save payload, canonical contract, generator path, or persisted revision that contains `NetworkReachability`.

## Boundary

`NetworkReachability` is a deterministic operational projection. `SegmentReachability` is the authored and persisted policy relationship. Phase 3 defense actions, policy diffs, and documentation changes are out of scope.
