# Vocabulary

Terms shared by more than one model page. Use them consistently across the
documentation and the thesis. Definitions are concise; each term's model page
states its precise semantics.

## Graph

- **Graph**: A network context model of nodes and edges. It has an immutable
  revision history.
- **Graph revision**: One immutable snapshot of a graph.
- **Optimized graph revision**: The new graph revision an optimization run
  creates after it applies its selected defense actions.

## Simulation

- **Simulation**: A Monte Carlo experiment on one graph revision.
- **Experiment**: The persisted record of one simulation and its trials.
- **Trial**: One independent attacker trajectory in a simulation.
- **Iteration**: One attacker action step within a trial.
- **Seed**: The deterministic random input for a simulation. Each trial derives
  its own seed from the simulation seed.
- **Baseline simulation**: The simulation on the source graph revision before
  defense.
- **Blast radius**: The number of foothold hosts at the end of a trial.
- **Mission impact**: The weighted impact of mission capabilities disrupted at
  the end of a trial.

## Optimization

- **Defense action**: One change selected to reduce modeled attack impact.
- **Strategy**: The method that selects defense actions under a budget.
- **Plan**: The actions selected by one strategy for one budget and selection
  seed.
- **Budget**: The maximum number of defense actions an optimization run may
  apply.
- **Pre-attack feasibility**: The condition where each mission capability is
  operational before attacker footholds are applied.

## Evaluation runner

- **Frozen manifest**: A manifest saved with an immutable graph revision. All
  warm-up and measured runs of a tier use it.
- **Warm-up run**: One unmeasured run that prepares the environment for a
  frozen manifest. It cannot be exported or analyzed.
- **Measured run**: One timed, exported run of a frozen manifest.
- **Replica**: One measured run among the repeats of the same frozen manifest.

Timing names: the study reports simulation, strategy-selection, and
total-evaluation durations. The runner and the analysis record the same values
as simulation, plan-selection, and total-evaluator durations. Strategy
selection is plan selection.
