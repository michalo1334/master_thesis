# Defenses and Optimization

This page states the current defense optimization model. It uses the canonical
terms in [vocabulary.md](vocabulary.md). It illustrates the rules on the
[shared micro-scenario](model-example.md).

## Defense actions

A defense action changes one element of the graph to reduce modeled attack
impact. An optimization run applies its selected actions to produce an
optimized graph revision.

Each current action removes the relationship or relationships that produce its
modeled effect. Removing them takes that effect away from the attacker.

| Action | Target | Relationship removed | Modeled effect |
| --- | --- | --- | --- |
| Patch vulnerability | a `has_vulnerability` edge | `has_vulnerability` | The host or service no longer exposes the vulnerability. The exploit rules no longer produce an exploit option for it. |
| Block segment policy | a `segment_reachability` edge | `segment_reachability` | Reachability is deny by default, so the derived flows for that segment pair no longer materialize. Attack reachability over that policy is removed. It can also remove a required flow. |
| Revoke credential | a `credential` node | every `authenticates_to` edge from the credential | The credential no longer authenticates. The credential-reuse rule no longer produces a reuse option against those services. |

## Unit action-count budget

Each current defense action has unit cost. A budget is the maximum number of
actions an optimization run may apply. Equal-action-count budgets therefore
compare plan cardinality, not money or deployment effort.

## Strategies

A strategy selects defense actions under a budget. Each strategy has a stated
purpose and a decision basis.

| Strategy | Purpose | Decision basis |
| --- | --- | --- |
| Null baseline | Apply no defense. Serve as a control reference. | None. It returns no actions. |
| CVSS | Mitigate the most severe vulnerabilities first. | Descending CVSS base score of each vulnerability. |
| Random | Select actions without prioritization. | Uniform random choice of action and target. |
| Topology segmentation | Shrink the set of hosts reachable from the declared foothold. | The reduction in reachable hosts from blocking each segment policy. |
| Simulation-informed | Select actions that reduce expected simulated damage. | Expected simulation result of each candidate; greedy. |
| Simulated annealing | Search for a low-damage plan within the budget. | Stochastic search over plans scored by simulation. |

The approved topology-scale study compares only the five non-null strategies.
The null baseline establishes the no-defense reference but is not part of that
ranking.

## Objectives and feasibility

An optimization run targets one objective:

- **Blast radius**: minimize the expected number of compromised compute
  resources.
- **Mission impact**: minimize the expected weighted impact of disrupted
  mission capabilities.
- **Lexicographic mission then blast radius**: minimize mission impact first,
  then use blast radius as the secondary tie-breaker.

Pre-attack feasibility decides whether a candidate action may be applied. When
enabled, an action is applied only if the resulting graph is feasible before
the attack, meaning every mission capability is operational with no attacker
foothold. An action that breaks a required flow, or drops support below a
capability's minimum, makes the graph infeasible. The run rejects such an
action and moves on. This prevents plans that break operational required flows
or mission support.

### Paired constrained and unconstrained comparison

To isolate the effect of feasibility, the system compares two plans produced by
the same strategy, objective, budget, and seeds. The constrained plan enables
pre-attack feasibility. The unconstrained plan disables it.

The comparison reports pre-attack measures directly, before any simulated
attack:

- feasibility result (feasible or not);
- unavailable (missing) required flows;
- affected mission capability statuses (operational or disrupted).

## One-action comparison

The shared scenario contrasts two single-action defenses against the same
attack path:

- **Patch `orders-rce`**: This removes the `has_vulnerability` edge. The remote
  exploit of `orders` no longer has an attack option. The required flow from
  `client-zone` to `orders` remains, so the capability stays operational. The
  action is feasible and is applied.
- **Block the `client-zone` to `service-zone` policy**: This removes the
  `segment_reachability` edge. It removes attack reachability to `orders`, but
  it also removes the required flow for the `order-processing` capability. The
  capability is disrupted before the attack, so the action is infeasible. When
  feasibility applies, the run rejects it.

The comparison shows why patching is selected and undifferentiated policy
blocking is not under the feasibility constraint.

## Source references

Behavior is established in the optimization and defense implementation:

- defense actions: `src/lib/network_defense/defense_actions/`;
- optimizer and default action set:
  `src/lib/network_defense/optimization/optimizer.ex`;
- strategy interface: `src/lib/network_defense/optimization/strategy.ex`;
- strategy registration:
  `src/lib/network_defense/optimizations.ex`;
- objectives: `src/lib/network_defense/optimization/simulation_objective.ex`;
- pre-attack feasibility:
  `src/lib/network_defense/simulation/mission_impact.ex`.
