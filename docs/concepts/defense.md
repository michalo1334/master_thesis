# Defenses and Optimization

Defense optimization selects changes to the context graph. Its goal is to
reduce modeled attack damage without exceeding an action budget. The
[model example](model-example.md) shows why a useful defense can still be
unacceptable when it disrupts the mission before an attack.

## Defense actions

A defense action removes graph relationships that enable an attack path. The
optimization appends a graph revision and preserves its source revision.

| Action               | Target                                   | Change                                                           | Modeled effect                                                                       |
| -------------------- | ---------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Patch vulnerability  | One `has_vulnerability` relationship.    | Remove the relationship.                                         | Exploit rules exclude the patched host or service weakness.                          |
| Block segment policy | One `segment_reachability` relationship. | Remove the relationship.                                         | Matching host-to-service flows disappear, including attack paths and required flows. |
| Revoke credential    | One `credential` node.                   | Remove all `authenticates_to` relationships from the credential. | Services reject authentication through the revoked credential.                       |

The [graph rules](graph.md) determine the effect of each action.

## Unit action-count budget

Each defense action has unit cost. A budget sets the largest number of actions
that an optimization run can apply.

An equal budget standardizes plan cardinality.

## Strategies

A strategy decides which actions to select under the budget.

| Strategy              | Purpose                                              | Decision basis                                        |
| --------------------- | ---------------------------------------------------- | ----------------------------------------------------- |
| Null baseline         | Provide a no-defense control.                        | Select no actions.                                    |
| CVSS                  | Address the most severe vulnerabilities first.       | Descending CVSS base score.                           |
| Random                | Provide a randomized benchmark.                      | Uniform random selection of an action and target.     |
| Topology segmentation | Reduce reachability from the initial foothold.       | Reduction in reachable hosts after each policy block. |
| Simulation-informed   | Reduce expected simulated damage.                    | Greedy comparison of simulated candidate outcomes.    |
| Simulated annealing   | Search beyond a greedy choice for a low-damage plan. | Stochastic search over plans scored by simulation.    |

Each strategy uses a different decision basis. The evaluation compares their
outcomes under the same action-count budget.

## Objectives and feasibility

An optimization run uses one objective:

- **Blast radius:** minimize the expected number of foothold hosts, including
  the initial foothold.
- **Mission impact:** minimize the expected weighted impact of disrupted
  mission capabilities.
- **Mission impact, then blast radius:** minimize mission impact first. Use
  blast radius only to break a tie.

A feasibility constraint protects the mission before the simulated attack. When
the constraint is active, the optimizer applies an action when every mission
capability remains operational before attacker footholds are applied.

An action is infeasible when it removes a required flow or reduces support
below a capability's minimum. The optimizer rejects that action and continues
the search. This rule prevents a defense plan from improving attack metrics by
breaking the mission itself.

### Paired constrained and unconstrained comparison

A paired comparison isolates the effect of the feasibility constraint. It runs
the same strategy with the same objective, budget, and seeds twice:

1. The constrained run rejects actions that cause pre-attack disruption.
2. The unconstrained run allows those actions.

The comparison records these pre-attack results:

- whether the graph is feasible;
- which required flows are unavailable; and
- which mission capabilities are disrupted.

## One-action comparison

The shared example compares two one-action plans against the same attack path.

### Patch `orders-rce`

Patching removes the `has_vulnerability` relationship and excludes the remote
exploit of `orders`. The required flow from `client-zone` to `orders` remains
available, so the `order-processing` capability stays operational. The action
is feasible.

### Block `client-zone` to `service-zone`

Blocking removes the `segment_reachability` relationship, attack reachability
to `orders`, and the required flow for `order-processing`. The capability is
disrupted before an attack. The feasibility constraint therefore rejects the
action.

A feasible defense reduces attack exposure while preserving the mission.
