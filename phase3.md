# Phase 3: Policy-Based Defense And Optimization

## Shared Context

Phases 1 and 2 persist canonical `SegmentReachability` policies and materialize transient `NetworkReachability` flows only for simulation and network projection. Optimizer actions and optimized revisions must remain canonical.

Existing development optimization runs that use `BlockReachability` are invalid. Discard them; do not add compatibility handling.

## Chunks

1. Replace `BlockReachability` with `BlockSegmentReachability`.
   - Target only canonical policy edges.
   - Update the registry, optimizer defaults, and generic-strategy tests.
   - Delete the retired action and empty unsupported strategies.

2. Rework topology segmentation ranking.
   - Rank each policy removal by the marginal reduction in reachable hosts after materialization.
   - Exclude zero-effect and overlapping-policy removals.
   - Preserve deterministic ordering and the optimizer's existing re-ranking after every action.

3. Update reports and dashboard terminology.
   - Describe source segment, target segment, protocol, and port range.
   - Describe a segment-boundary cut, not host/service segmentation.
   - Keep operational flow counts explanatory, never actionable.

## Checks

- Targeted defense-action, strategy, materialization, report-contract, LiveView, and dashboard Vitest tests.
- `mix gen.contracts`, `npm run typecheck`, and `mix precommit`.
- Verify optimized revisions remove canonical policies only and rematerialization removes only flows uniquely enabled by each policy.
