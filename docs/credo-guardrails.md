# Repository Credo guardrails

These checks protect local conventions. They do not identify AI-authored code or replace review. The [design and research](../planning/credo-guardrails/design.md) explain why each rule exists.

## Run

From `src/`, with the locked Mix dependencies installed:

```bash
mix credo.test
MIX_ENV=test mix credo --strict
MIX_ENV=test mix credo -C project_strong
MIX_ENV=test mix credo -C project_heuristics
```

`credo.test` runs the new AST tests without PostgreSQL or application startup. Normal `mix test` also discovers them. The existing error-code check is tested separately by the normal suite; the focused command is not a replacement for it.

The default profile retains existing Credo and ExSlop checks. The named profiles isolate the new strong rules and heuristics. Heuristic findings remain visible but have zero exit status; the default profile can still fail for other checks.

## Strong rules

| Check | What to do instead |
| --- | --- |
| `FlattenedProjectionContract` | Declare projection contracts as nested children, not flattened names. |
| `RetiredProjectionTypeHelper` | Use the existing node and relationship registries instead of restoring the retired root-contract helpers. |
| `LiveViewRepoDependency` | Call a domain API from LiveView code instead of depending directly on the project Repo. |

The first two rules follow a [recorded review and refactor](../planning/credo-guardrails/research/history.md). The LiveView boundary is a newly stated policy consistent with the current source; it is not attributed to an earlier user request. Health and telemetry database probes are outside that rule's path scope.

## Advisory rules

- `InlineContractTypeMapping`: review a private contract function with at least three literal atom-to-string clauses. A registry may own it, but independent wire labels can be valid.
- `SuccessShapedExitCatch`: review an exit catch that directly returns a success-shaped value. Cleanup can legitimately succeed after the target process exits; a failed business operation may not.

Read the code before extracting a helper or changing failure behavior. Keep justified exceptions visible, or use a narrowly scoped Credo suppression with a reason. Do not disable a whole class merely to make output quiet.

## Limits

The namespace checks resolve literal nested declarations and explicit `Elixir.` qualification. They do not expand aliases or dynamic module names. Repo detection checks explicit literal references; it does not follow dynamic dispatch, inherited aliases, or transitive dependencies.

The checks skip quoted code and do not expand macros. Literal mappings and catch return shapes are local syntax, not whole-program behavior. A missing finding is not proof of correct ownership, error handling, or security.

See [verification](../planning/credo-guardrails/verification.md) for actual command outcomes and profile fixtures. CI runs the normal test suite and default Credo; it does not separately run every named-profile experiment.
