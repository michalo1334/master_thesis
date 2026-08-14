# Vocabulary

Use these terms consistently in the dashboard, documentation, and thesis.

## Graphs

- **Graph**: A network context model. It has an immutable revision history.
- **Graph revision**: One immutable snapshot of a graph.
- **Optimized graph revision**: The revision created by an optimization run after it applies its selected defense actions.

## Simulations

- **Simulation**: A Monte Carlo experiment on one graph revision.
- **Experiment**: The persisted record of one simulation and its trials.
- **Trial**: One independent attacker trajectory in a simulation.
- **Iteration**: One attacker action step within a trial.
- **Seed**: The deterministic random input for a simulation. Each trial derives its own seed from the simulation seed.
- **Baseline simulation**: A simulation on the source graph revision before optimization.
- **Post-optimization simulation**: A simulation on the optimized graph revision using the baseline simulation configuration.
- **Blast radius**: The number of compromised compute resources at the end of a trial.
- **Mission impact**: The weighted impact of mission capabilities disrupted at the end of a trial.

## Optimization

- **Defense action**: One change selected to reduce modeled attack impact.
- **Strategy**: The method that selects defense actions under a budget.
- **Budget**: The maximum number of defense actions an optimization run may apply.
- **Optimization run**: One execution of a strategy against a graph revision. It produces an optimized graph revision.

## Reports

- **Combined analysis**: The dashboard flow that runs a baseline simulation, one optimization run, and a post-optimization simulation in sequence.
- **Comparison report**: A dashboard report that compares a combined analysis's baseline and post-optimization simulation, and shows the selected optimization plan. It is distinct from a graph diff, which compares graph structure.

See [the system model](model.md) for model semantics and [the use cases](usecases.md) for dashboard workflows.
