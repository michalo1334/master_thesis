# Master Thesis — Graph-Based Attack Simulation and Defense Optimization

A system for graph-based simulation of attack propagation in computer networks and automated evaluation of defensive actions aimed at reducing attack blast radius.

The project combines network topology modeling, stochastic attack simulation, vulnerability data, and defense optimization. Network infrastructure is represented as a graph, while attack propagation is evaluated dynamically using vulnerability preconditions, attacker characteristics, and probabilistic simulation.

The system does not require the construction of a complete static attack graph or the prior enumeration of every possible attack path. Attack paths may emerge dynamically during simulation.

## Project scope

The project covers the following areas:

* **Master's thesis** — graph-based attack-propagation simulation and evaluation of automated defense strategies for reducing the impact of network attacks.
* **Self-development security project** — demonstration of self-hosted infrastructure represented alongside synthetic network components, including vulnerability modeling and the application of patches and network controls.
* **Future extension for the `Konkurs imienia Mariana Rejewskiego`** — extension of blast-radius evaluation with asset-specific impact weights, allowing compromised hosts to contribute differently to the total attack impact. See `docs/initial/konkurs_rejewski_top_rozszerzenia_pracy.md`.

# Master's thesis

## Working title

> **Graph-Based Attack Path Simulation and Automated Defense Optimization for Blast Radius Minimization in Computer Networks**

In this work, *graph-based* refers to representing network topology and security-relevant relationships as a graph. It does not imply that a complete static attack graph must be constructed before simulation.

## Main research question

> To what extent can graph-based attack-propagation simulation combined with automated defense optimization reduce the expected blast radius of network attacks compared with conventional vulnerability-based defense prioritization methods?

## Research sub-questions

1. **How do network topology, vulnerability preconditions, and attacker profiles influence simulated attack propagation and the resulting blast-radius distribution?**

2. **How effectively do simulation-informed patching, network segmentation, and hybrid defense strategies reduce the expected blast radius compared with vulnerability-based and topology-based prioritization methods under a constrained defense budget?**

3. **How do the computational cost and stability of the proposed approach scale with network size, topology density, vulnerability density, and the number of Monte Carlo simulation runs?**

## Research scope

The research evaluates whether information obtained from attack-propagation simulation can improve defensive decision-making compared with simpler vulnerability- and topology-based prioritization approaches.

The evaluated defense strategies may include:

* vulnerability-score-based patch prioritization;
* topology-based defense prioritization;
* simulation-informed vulnerability patching;
* graph-based network segmentation;
* hybrid patching and segmentation strategies.

Evaluation metrics may include:

* expected blast radius;
* median and upper-percentile blast radius;
* blast-radius variance;
* probability of compromising critical assets;
* expected blast-radius reduction;
* blast-radius reduction per unit of defensive cost;
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
* **NVD API** — real CVE and vulnerability data.
* **OpenTelemetry, Grafana, Tempo, Loki, Prometheus, and Grafana Alloy** — tracing, metrics, logging, and application observability.
* **Python** — statistical analysis and evaluation of experimental results.
* **LuaLaTeX, Minted, and TikZ** — master's thesis typesetting, source-code presentation, and technical diagrams.

# Quick start

```bash
cd infra/environments/local
./terraform.sh init
./terraform.sh apply
```

# Links

* Repository: https://github.com/michalo1334/master_thesis
