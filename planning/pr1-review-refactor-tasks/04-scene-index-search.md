# Chunk 04: Scene Index and Search

## Objective

Address comments `4111196522` and `4111196757`.

## Scope

- Add a graph-level topology scene index outside the `unified/` renderer folder.
- Expose flat segment, host, and service entries with parent context.
- Define `projectedEntityIds` as segment, host, and service IDs only.
- Reuse the index in search.
- Extract search match ranking from nested conditional expressions.
- Reuse the index in other graph-level callers only when it removes clear duplication without adding an import inversion.

## Constraints

- Search does not filter or mutate the scene.
- Preserve prefix, substring, and type-match precedence.
- Preserve deterministic path labels and result limits.
- Do not treat unplaced floaters as projected entity IDs.

## Acceptance

- Search has no nested segment-host-service loop.
- Ranking is a named pure function with focused tests.
- The index preserves projection order and parent links.

## Checks

Run topology scene, search, toolbar, lens, and Unplaced tests. Run typecheck and formatting.
