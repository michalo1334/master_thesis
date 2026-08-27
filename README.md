# Master Thesis — Graph-Based Attack Simulation and Defense Optimization

A system for graph-based simulation of attack propagation in computer networks and simulation-based comparison of defensive actions. Defenses aim to reduce modeled mission impact; blast radius is a secondary safety outcome.

The model combines network topology, stochastic state-transition simulation, and defense optimization. Vulnerabilities carry CVSS characteristics and a separately assigned, stylized success probability. The simulator selects uniformly from eligible actions, then samples the selected action's outcome. It does not estimate real-world exploit likelihood.

The system does not require a complete static attack graph or prior enumeration of every attack path. Attack paths may emerge dynamically during simulation.

## Documentation map

- [Scope, assumptions, and limits](docs/concepts/scope.md) — project boundaries and research questions.
- [Functional requirements](docs/concepts/requirements.md) — current, externally observable behavior.
- [Context graph and reachability](docs/concepts/graph.md) — node and relationship model.
- [Attack simulation and mission impact](docs/concepts/attack.md) — attacker model and simulation loop.
- [Defenses and optimization](docs/concepts/defense.md) — defense actions and strategies.
- [Evaluation lifecycle](docs/concepts/evaluation.md) — manifest-driven evaluation runner.
- [Shared example](docs/concepts/model-example.md) — one concrete micro-scenario.
- [Vocabulary](docs/concepts/vocabulary.md) — shared model terms.
- [Architecture](docs/architecture.md) — system, container, and deployment views.
- [Infrastructure](docs/infrastructure.md) — local provisioning and lifecycle.
- [Dashboard design](docs/design/dashboard.md) — browser workflows.
- [Analysis guide](evaluation/analysis/README.md) — statistical analysis service.
- [Thesis source](thesis/) — tracked LaTeX source of the thesis.

## Repository map

```text
master_thesis/
├── docs/          — Concepts, architecture, infrastructure, and design
├── src/           — Elixir simulation engine and web application
├── evaluation/    — Analysis service and scenarios
├── infra/         — Terraform infrastructure and local runtime configuration
├── thesis/        — LaTeX source of the master's thesis
└── planning/      — Working planning documents
```

## Quick start

The local environment runs a Terraform-managed Docker stack. See the [infrastructure guide](docs/infrastructure.md) for prerequisites, configuration, and teardown.

Run Terraform through the local helper:

```bash
cd infra/environments/local
./terraform.sh init
./terraform.sh apply
```

## Repository

- Repository: https://github.com/michalo1334/master_thesis
