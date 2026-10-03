# Credo guardrails

## Design

The project already runs strict Credo, ExSlop, Dialyzer, and Sobelow. Add small repository policies, not another general lint framework or an AI-authorship detector. See the [Elixir research](research/elixir-patterns.md), [ExSlop/ExDNA and AI evidence](research/exslop-exdna-ai.md), and [correction history](research/history.md).

### Checks

| Check | Class | Exact scope and signal | Alternative / limit |
| --- | --- | --- | --- |
| `FlattenedProjectionContract` | Strong | An Elixir module declaration directly extends `NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection` in the same final name segment, such as a flattened child name | Use a nested child module. Other contract families are outside this rule. |
| `RetiredProjectionTypeHelper` | Strong | The exact root projection contract defines private `node_type/1` or `relationship_type/1` helpers | These retired names mark the regression fixed in `d40d463`. Use the node/relationship registries. This does not prove that every mapping uses a registry. |
| `LiveViewRepoDependency` | Strong | A source file under `lib/network_defense_web/live/` explicitly aliases, imports, requires, uses, or directly calls `NetworkDefense.Repo` | Call a domain API. This newly stated boundary follows current code; it is not attributed to an earlier review request. Health and telemetry are outside the path scope. Dynamic dispatch and transitive calls are not analyzed. |
| `InlineContractTypeMapping` | Heuristic | Within a web contract module, at least three clauses of one private arity-one function map literal atoms to literal strings | Review whether a registry owns the mapping. Presentation labels and independent wire enums may be valid. Exclude the two retired helper names to avoid duplicate reports. |
| `SuccessShapedExitCatch` | Heuristic | A `catch` clause handles literal `:exit` and its body directly returns `:ok`, `nil`, an empty list/map, or an `{:ok, value}` tuple | Review whether a failed operation becomes an apparent success. Cleanup and deliberate fallback can be valid. This checks catch, not ExSlop's existing rescue rules. |

These are source-shape policies. Do not run application functions from these checks. Do not expand macros or inspect runtime behavior. Skip quoted AST data. Resolve only syntax needed by the declared rules, and document unsupported forms rather than guess.

Strong findings fail the normal Credo gate. Heuristic findings have zero exit status and clear review wording. Separate named profiles expose only strong or heuristic project checks. Keep existing checks and their behavior in the default profile; do not hide existing debt or promote all ExSlop findings to errors.

Messages name the violated policy and the relevant alternative. No automatic fixes. No claim that a finding identifies AI-authored code.

### Verification cases

- When a flattened projection child is declared, the strong check shall report its definition line.
- When a valid nested projection child or unrelated module is declared, the namespace check shall report no issue.
- When the root projection contract defines either retired private arity-one helper, the check shall report it.
- When another module uses the same helper name, the retired-helper check shall report no issue.
- When a LiveView file explicitly depends on the project Repo, the boundary check shall report the dependency.
- When domain code, health checks, or telemetry use Repo, the LiveView-only check shall report no issue.
- When a web contract repeats a literal atom-to-string mapping across at least three clauses, the heuristic shall request review.
- When a mapping is short, public, computed, or outside web contracts, that heuristic shall report no issue.
- When an exit catch returns a success-shaped literal, the heuristic shall request review.
- When an exit catch returns a tagged error, reraises/exits, or calls a helper, that heuristic shall report no issue.
- When matching syntax occurs only inside a quote, no new check shall report it.
- When a CLI fixture has a strong violation, the strong profile shall exit nonzero.
- When a CLI fixture has only a heuristic finding, the heuristic profile shall display it and exit zero.

Test values must be synthetic. Policy identifiers necessarily match the rule's explicit namespace; scenario names, atoms, strings, and code bodies must not copy application examples verbatim.

## Execution

1. Implement the five checks and focused positive/negative tests. Use the existing Credo check loading convention. Share only small AST utilities that genuinely reduce duplication.
2. Integrate checks into default, `project_strong`, and `project_heuristics` configurations. Add a database-independent test command if needed; retain normal test discovery and CI/precommit coverage.
3. Exercise actual CLI findings and exit statuses with disposable fixtures. Run the checks over this repository and review every new finding. Do not suppress findings merely to obtain green output.
4. Run relevant tests, format checks, default Credo, and existing gates where available. Record baseline failures separately and do not claim a full green run without evidence.
5. Main agent reviews implementation, writes the concise usage guide, and checks the goal audit before scoped commits.
