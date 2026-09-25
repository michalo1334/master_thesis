# Chunk 01: Domain Projector

## Objective

Add the pure Elixir topology projector and a safe graph-contract conversion path.

## Scope

- Add `src/lib/network_defense/graph/topology_projection.ex`.
- Add `GraphContract.to_domain/2` in `src/lib/network_defense/graph/contracts/graph_contract.ex`.
- Add `src/test/network_defense/graph/topology_projection_test.exs`.
- Extend `src/test/network_defense/graph/contracts_test.exs`.

## Required behavior

`TopologyProjection.project/1` returns deterministic arrays for:

- segments with host IDs and counts;
- hosts with segment IDs, service IDs, and counts;
- services with host IDs;
- attached vulnerabilities, credentials, and mission capabilities with typed anchors and source edge IDs;
- grouped segment policies, including self-policy;
- grouped operational flows from `MaterializeReachability.operational_flows/1`;
- typed placement issues.

Support these issue codes:

- `host_without_segment`;
- `host_multiple_segments`;
- `service_without_host`;
- `service_multiple_hosts`;
- `context_without_anchor`.

`GraphContract.to_domain/2` reuses `Graph.hydrate/4`. With `validate_membership: false`, it accepts incomplete ownership. It still rejects malformed or dangling edges.

Port useful semantic fixtures from `NetworkCanvasProjection.test.ts`. Do not edit browser production code.

## Acceptance

- The projector has no web or browser dependency.
- Identical graphs produce identical array order.
- Every issue code has a focused test.
- Contract conversion tests cover valid, incomplete, malformed, and dangling graphs.

## Focused checks

Run the projector test and graph-contract tests. Run the Elixir formatter for changed Elixir files.
