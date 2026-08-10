# Master Thesis — Graph-Based Attack Simulation and Defense Optimization

A system for graph-based simulation of attack propagation in computer networks and simulation-based comparison of defensive actions aimed at reducing modeled blast radius.

The project combines network topology modeling, stochastic state-transition simulation, vulnerability data, and defense optimization. Vulnerabilities carry CVSS severity characteristics and a separately assigned, stylized success probability. The simulator selects uniformly from eligible actions, then samples the selected action's outcome; it does not estimate real-world exploit likelihood.

The system does not require the construction of a complete static attack graph or the prior enumeration of every possible attack path. Attack paths may emerge dynamically during simulation.

## Project scope

The project covers the following areas:

* **Master's thesis** — graph-based attack-propagation simulation and evaluation of automated defense strategies for reducing the impact of network attacks.
* **Self-development security project** — demonstration of self-hosted infrastructure represented alongside synthetic network components, including vulnerability modeling and the application of patches and network controls.
* **Mission-impact extension** — evaluates disruption of weighted mission capabilities with declared technical dependencies and redundancy thresholds.

# Master's thesis

## Working title

> **Graph-Based Attack Path Simulation and Automated Defense Optimization for Blast Radius Minimization in Computer Networks**

In this work, *graph-based* refers to representing network topology and security-relevant relationships as a graph. It does not imply that a complete static attack graph must be constructed before simulation.

## Main research question

> Within a fixed stylized network, policy, and attacker model, how can context-graph simulation support comparison of equal-action-count defensive choices with CVSS-priority ordering?

## Research sub-questions

1. **How do modeled topology and vulnerability preconditions influence simulated attack propagation under the fixed attacker model?**

2. **Under an equal-action-count budget, how do simulation-informed patching, policy segmentation, and simulated-annealing search select actions relative to vulnerability- and topology-based priorities?**

3. **What versioned runner, inputs, and result artifacts are required before measuring stability, runtime, or sensitivity to topology and vulnerability density?**

## Research scope

The current scope is one fixed stylized topology, policy, and attacker model. It supports only equal-action-count budgets because each current defensive action has unit cost. A reproducible evaluation runner and result artifacts are pending.

The model cannot substantiate claims about real lateral movement, deployable cost-aware segmentation, sensitivity to topology density or attacker profiles, or general scalability beyond scenarios that are measured and reported.

The evaluated defense strategies may include:

* vulnerability-score-based patch prioritization;
* topology-based defense prioritization;
* simulation-informed vulnerability patching;
* policy-based network segmentation;
* simulated-annealing optimization over patching and segmentation actions.

Evaluation metrics may include:

* expected blast radius;
* median and upper-percentile blast radius;
* blast-radius variance;
* probability of disrupting each mission capability;
* expected blast-radius reduction;
* blast-radius reduction per unit of defensive cost, after non-unit costs are modeled;
* simulation and optimization runtime;
* memory usage;
* convergence and stability of Monte Carlo estimates.

# Repository layout & links to documents

```text
📁 master_thesis/  — Attack simulation and automated defense optimization
├── 📁 docker/        — Observability configuration and initialization scripts
│   ├── 📁 grafana-dashboards/
│   └── 📁 grafana-provisioning/
├── 📁 docs/          — ADRs, concepts, research notes, wireframes, and thesis drafts
│   ├── 📁 adr/
│   ├── 📁 concepts/
│   ├── 📁 initial/
|   ├── 🗎 architecture.md
|   └── 🗎 infrastructure.md
├── 📁 src/           — Elixir simulation engine and web application
├── 📁 infra/         — Terraform infrastructure
└── 📁 thesis/        — LaTeX source of the master's thesis
```

# Technology stack

* **Elixir** — attack simulation and defense optimization.
* **PostgreSQL** — persistent application, network, vulnerability, and simulation data.
* **Phoenix LiveView, LiveSvelte, Svelte 5, Bits UI, and Tailwind CSS** — browser-based visualization and management of network topology, simulations, and defensive actions.
* **NVD API** — planned source of real CVE and vulnerability data.
* **OpenTelemetry, Grafana, Tempo, Loki, Prometheus, and Grafana Alloy** — tracing, metrics, logging, and application observability.
* **Python** — planned statistical analysis of experimental results.
* **LuaLaTeX, Minted, and TikZ** — master's thesis typesetting, source-code presentation, and technical diagrams.

# Quick start

```bash
cd infra/environments/local
./terraform.sh init
./terraform.sh apply
```

# Links

* Repository: https://github.com/michalo1334/master_thesis
