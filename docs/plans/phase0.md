# Phase 1 Implementation Plan

1. Clear legacy graph and optimization records before deployment. Do not migrate direct host-to-service flows.
2. Add `SegmentReachability` with protocol and port-range validation. Make `NetworkReachability` an empty internal marker.
3. Keep operational reachability registered for transient simulation graphs, but exclude it from canonical contracts, connection drafts, connectivity replies, and persisted revisions.
4. Require exactly one incoming `Contains` edge for every host and exactly one incoming `Runs` edge for every service when hydrating canonical graphs.
5. Remove protocol and port matching from the two simulation rules. Operational edges already represent effective flows.
6. Regenerate TypeScript contracts after replacing canonical reachability data with segment-policy data.
7. Remove direct-flow authoring from both canvas views. Use the existing generic connection flow and inspector for segment-policy creation and editing.
8. Rewrite seeds and affected fixtures with segments, ownership edges, and policy rules.
9. Verify focused backend and frontend tests, then run `mix precommit`.

## Boundary

`NetworkReachability` may exist only in an in-memory operational graph. `SegmentReachability` is the persisted policy edge.
