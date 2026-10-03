# Repository correction evidence

An explorer inspected saved Git history, current source, and `planning/pr1-review-comments.md`. The comments refer to PR 1 at `5b5e88567d17e0457a8da9f2f58a961f4082a021`. Commit `d40d463` contains the correction. A commit message alone does not prove that a change was requested by the user.

| Evidence | Correction | Static-analysis implication |
| --- | --- | --- |
| Review comment `4111204706`: use `TopologyProjection` submodules | Flattened projection contracts became nested contracts under `NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection` | An exact namespace regression is a strong signal. Do not impose this naming rule on unrelated modules. |
| Comment `4111209798`: reuse helpers that convert atoms and types | `topology_projection.ex` replaced local `node_type/1` and `relationship_type/1` clauses with registry functions | Prevent the retired helper definitions from returning. Other inline mappings are only candidates for review. |
| Comments on repeated loops, geometry, and canvas code | The refactor extracted scene indexes and view-model helpers | Repetition was a real maintenance concern. It does not justify a blanket ban on loops or a second clone engine. |
| Comments asking about one-to-many relationships; refactor design explains normalized cross-references | Owned records and ID references retain different representations | Do not mechanically replace every ID array with an embedded collection. The reviewed design deliberately preserves references. |
| Current web source has direct `Repo` references only in the health controller and telemetry module | LiveView adapters call domain APIs instead | A LiveView-only persistence boundary is consistent with current code, but is a newly stated policy, not a documented prior user request. |

Current evidence paths:

- `src/lib/network_defense_web/contracts/dashboard/graph/topology_projection.ex`
- `src/lib/network_defense_web/contracts/dashboard/graph/topology_projection/`
- `src/lib/network_defense_web/controllers/health_controller.ex`
- `src/lib/network_defense_web/telemetry.ex`
- `planning/pr1-review-comments.md`
- `planning/pr1-review-refactor-plan.md`

Credo strict-mode work already exists in `e1009c1`, merged by `4011d54`. Keep its gate. The existing `ErrorCodesMatchType` check is not new work for this goal.

## Rejected extrapolations

Do not call every rescue wrong, infer authorization from a function name, or treat structural similarity as proof of shared ownership. Existing ExSlop checks already cover several generic rescue, query, and Enum patterns. The new checks must state their narrower limits.
