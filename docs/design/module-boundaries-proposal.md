# Proposal: enforce Elixir module boundaries

Status: in progress. The outer boundaries are implemented. The next work tightens these boundaries and adds inner boundaries.

## Recommendation

Adopt [Boundary](https://github.com/sasa1977/boundary) from the outside inward. Start with wide outer boundaries that describe the current architecture. Tighten their exports and dependencies in small steps. Then extract inner boundaries.

Use this extraction order:

1. Define wide outer boundaries.
2. Tighten each boundary as the code makes its public interface clear.
3. Extract modules that already have clean dependency directions.
4. Refactor and extract the coupled modules last.

This order gives immediate enforcement without requiring a large initial rewrite. Boundary checks module dependencies during compilation. It fits the existing Phoenix application without an umbrella conversion or runtime service split.

## Audit findings

The current source contains 443 `defmodule` declarations. The largest groups are Study (140), web (141, including 123 contract modules), Graph (37), Optimization (19), Simulation (16), and Compute (9). These counts exclude generated protocol implementation modules.

| Finding | Evidence under `src/lib/` | Adoption impact |
| --- | --- | --- |
| The domain root contains documentation only. | `network_defense.ex` | Define an explicit export list; the root does not currently provide a facade. |
| Dashboard code uses graph models, graph services, and several execution contexts directly. | `network_defense_web/live/web/dashboard/dashboard_live.ex:10–18` | Review these dependencies individually. Some models are legitimate public values. |
| Study already documents a supported facade and public values. The web layer also calls `Lifecycle.active?/1`. | `network_defense/evaluation2/study.ex:1–42`; `network_defense_web/study_requests.ex:234` | Study is the best first internal boundary. Decide whether active-state classification belongs in its public API. |
| Graph and Nodes reference each other. Actions and AttackerState also reference each other. | `network_defense/graph/graph.ex:7`; `network_defense/nodes/network_segment.ex:4`; `network_defense/attacker_state/attacker_state.ex:7`; `network_defense/actions/reuse_credential.ex:20` | Keep these groups together initially. Splitting every directory would create dependency cycles. |
| Simulation implements Compute's behaviour, while Compute names the concrete simulation operation. Rules also consume simulation run values. | `network_defense/simulation/simulation_operation.ex:4–8`; `network_defense/compute/rabbit_mq/envelope.ex:5`; `network_defense/rules/acquire_credential_rule.ex:17` | Separate operation contracts and transport registration before enforcing independent boundaries. |
| Aggregate errors depend on domain errors; graph contracts depend on the aggregate. | `network_defense/errors.ex:4–6`; `network_defense/graph/contracts/graph_contract.ex:6` | Remove this reverse dependency before extracting Graph. |
| The web health controller queries Repo directly. | `network_defense_web/controllers/health_controller.ex:7` | Put readiness behind a small application API so Repo can remain private. |
| Actions, rules, defenses, and strategies use `defimpl`. | For example, `network_defense/actions/reuse_credential.ex:19` | Explicitly classify implementations; Boundary skips their outgoing calls by default. |

Repository access inside persistence contexts is expected. Public value types and schemas also require deliberate exports. Boundary should enforce ownership without forcing a rewrite of these interfaces.

## Proposed boundary structure

Boundary assigns ordinary modules by namespace. The first stage uses wide boundaries and permissive exports. Later stages tighten them:

| Boundary | Responsibility and allowed access |
| --- | --- |
| `NetworkDefense` | Existing domain code. Export reviewed service modules, public values, contracts, and required shared helpers. Depend on the Repo boundary. |
| `NetworkDefense.Repo` | Top-level infrastructure boundary. Permit domain and application startup access; omit it from web dependencies. |
| `NetworkDefenseWeb` | Phoenix and wire contracts. Depend on the domain's exports. Export the endpoint, telemetry, and metrics plug required by startup. |
| `NetworkDefense.Application` | Top-level composition boundary. Wire domain infrastructure and web services through explicit exports or dependencies. |
| Proposed `NetworkDefense.Tooling` | Mix commands and contract generation. Reclassify Mix tasks here. Move ordinary helpers such as `Mix.Study.Command` under this namespace. |
| Proposed test-support root | Compile only in tests. Allow access to internals through a dedicated boundary with incoming/outgoing checks disabled. Move support modules out of production namespaces. |

After the outer structure is stable, tighten one boundary at a time. Replace broad exports with reviewed service modules, public values, contracts, and required shared helpers.

Then add `NetworkDefense.Evaluation2.Study` as a nested boundary. Export the facade and its public response, authoring, error, and result types, including nested values used by wire conversion. Keep Persistence, Workflow, and Compute implementation modules private. Provide a supervision entry point for Study processes that startup currently names directly. Re-export approved Study modules through `NetworkDefense` for web and tooling callers.

After Study, extract other modules that already have clean dependency directions. Retain Graph, Nodes, Actions, Rules, Simulation, and Optimization in the parent boundary until their dependencies are ready. Extract these coupled groups last. Their extraction requires cycle removal, shared-contract placement, and namespace alignment.

## Rollout and verification

1. **Establish wide outer boundaries.** Add Boundary `~> 0.12` with `runtime: false`. Prepend its compiler while retaining the existing LiveView compiler. Classify Mix tasks and protocol implementations. Separate test support. Use broad exports where the public interface is not yet clear.
2. **Tighten the outer boundaries.** Review one dependency path at a time. Replace broad exports with explicit exports. Add small facade functions when a caller currently reaches into implementation modules.
3. **Protect Study.** Add the nested boundary and explicit exports. Replace web calls to private helpers with supported API calls. Check that web and CLI callers cannot access Persistence or Workflow.
4. **Extract clean groups.** Add boundaries for modules that already have one-way dependencies and clear public interfaces. Keep each change small and compile after each extraction.
5. **Prepare and extract coupled groups.** Remove dependency cycles before adding their boundaries. Remove the aggregate-error reverse dependency. Move operation registration to composition or configuration while retaining the transport allowlist. Separate shared run contracts from rules and simulation implementations before extracting Compute and execution boundaries.

Enable alias checks to catch module-valued references such as transport operation registrations. Defer global strict external-dependency checks: domain contracts currently use Ecto, and progress publication uses Phoenix PubSub.

Use `mix compile --force --warnings-as-errors` in development and test verification. CI and `precommit` currently spell the option `--warning-as-errors`; replace it with the plural option Boundary reads. Verify production compilation and the release build too.

Acceptance requires zero Boundary diagnostics, a passing test suite, unchanged generated TypeScript contracts, and negative checks for forbidden web-to-Repo, web-to-Study-internal, and domain-to-web calls. Restrict temporary `dirty_xrefs` exceptions to named modules with a removal task.

## Limits and sources

Boundary checks compiler-visible references. Dynamic dispatch, persisted worker-name strings, and runtime messages still need tests. Compatibility with this project's Elixir/OTP versions requires the compile trial in step 1.

Sources checked: [Boundary 0.12.0 package](https://hex.pm/packages/boundary/0.12.0), [boundary definitions](https://hexdocs.pm/boundary/0.12.0/Boundary.html), and [compiler behaviour](https://hexdocs.pm/boundary/0.12.0/Mix.Tasks.Compile.Boundary.html). The published package source confirms namespace ownership, nested exports, optional alias checks, protocol classification, and warning enforcement.
