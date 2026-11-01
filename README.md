# Network Defense

Network Defense is a master's thesis project for modeling computer networks, simulating attack propagation, and comparing defenses under a fixed action budget. It compares vulnerability patches, segmentation changes, and credential revocation through their effects on mission capabilities and host compromise.

The system is a research simulator, not a penetration-testing tool. Success probabilities are scenario inputs, not estimates of real-world exploit likelihood. Attack paths emerge during simulation rather than being enumerated in advance.

## Core workflows

### Network modeling

The topology represents hosts, services, and their dependencies within network segments. Saved graph revisions provide fixed inputs for simulation and comparison.

![Network topology with hosts and services grouped into segments](docs/images/topology.png)

### Attack simulation

Repeated simulations estimate blast radius, mission impact, and host compromise probabilities. Reports show aggregate outcomes and variation between runs.

![Completed attack simulation report](docs/images/simulation.png)

### Defense optimization

Defense strategies select actions within a fixed budget. Reports list the selected defenses and the resulting graph changes.

![Completed defense optimization with selected actions](docs/images/defenses.png)

## Local setup

The local environment requires Linux, Git, a running Docker engine, and Python 3. Terraform, Elixir, Node, and the databases run in containers. The environment includes two application sites and observability services.

```bash
git clone https://github.com/michalo1334/master_thesis.git
cd master_thesis/infra/environments/local
./terraform.sh init
./init-secrets.py
./terraform.sh plan
./terraform.sh apply
./terraform.sh output urls
```

Terraform presents the plan for review before provisioning. The secret helper creates missing random secret files with owner-only permissions and preserves existing values. Required paths come from Terraform configuration.

The `application` entry in the URL output identifies the dashboard. A small example workflow is:

1. **Create document → Graph → Enterprise Topology (15 hosts)** opens the seeded topology. **Arrange** lays out its nodes.
2. The **Simulation** example uses foothold `workstation-4`, 100 trials, 100 iterations, and seed 0. **Simulate** starts the run.
3. **Optimization** operates on the graph tab. The example uses **CVSS** and a budget of 3; **Optimize** starts defense selection.

These are example inputs, not recommended research settings.

The [infrastructure guide](docs/infrastructure.md) covers configuration and lifecycle details. This development stack is intended for local use; it is not a hardened public deployment.

Running `./terraform.sh destroy` from the same directory removes the stack. **This deletes its database and other managed data volumes.** Host secret files remain.

## Repository guide

- **Model:** [scope and limits](docs/concepts/scope.md), [requirements](docs/concepts/requirements.md), [graph and reachability](docs/concepts/graph.md), [attack simulation](docs/concepts/attack.md), [defenses](docs/concepts/defense.md).
- **Research workflow:** [native study overview](docs/concepts/evaluation-study-overview.md), [operator guide and create-to-result example](docs/evaluation2.md), [methodology](docs/concepts/evaluation-methodology.md), [native architecture](docs/architecture/evaluation-architecture.md), [pipeline and timing](docs/design/evaluation-study-pipeline.md), [verification record](docs/history/evaluation2-verification.md), [decision history](docs/history/evaluation-decisions.md), [model example](docs/concepts/model-example.md), [vocabulary](docs/concepts/vocabulary.md).
- **Engineering:** [architecture](docs/architecture.md), [dashboard](docs/design/dashboard.md), [RabbitMQ executor](docs/design/rabbitmq-distributed-executor.md).

Native Evaluation2 implements YAML revision creation, Pilot planning, explicit Final approval, sequential tier collection and in-process statistical analysis. The supported API is `NetworkDefense.Evaluation2.Study`; `mix study.*` supplies thin operator commands. Each Final tier has excluded warm-up and five measured replicas. The result stores timing triplets; helpers derive medians and observed ranges.

Three real local service-backed studies reached durable success at small counts. All used insufficient-Pilot overrides and returned wide intervals. The complete prespecified calibration passed its declared model-grid checks, and the obsolete implementation is removed. See the [verification record](docs/history/evaluation2-verification.md) for evidence and limits. The [identity-free YAML template](docs/examples/evaluation2-study.yaml) requires local graph/Host identities before use.

The Elixir/Phoenix application and Svelte UI live in [`src/`](src/); provisioning lives in [`infra/`](infra/). [`docs/`](docs/) holds project documentation. The thesis text is maintained separately.
