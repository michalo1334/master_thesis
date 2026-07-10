# Graph-Based Attack Simulation and Blast Radius Minimization

## Research Question

> To what extent can graph-based attack simulation combined with automated defense optimization reduce the blast radius of network attacks compared to conventional vulnerability prioritization methods?

### Sub-questions

1. How effectively does graph-based attack path modeling capture real-world lateral movement patterns?
2. Which optimization strategy (graph min-cut for segmentation, greedy patching, or hybrid) achieves the greatest blast radius reduction per defensive action?
3. How does the approach scale with network size and complexity?

## Expected Contributions

1. **A graph-based attack simulation model** that maps network topology + vulnerability data into an attack graph and simulates attacker progression using probabilistic lateral movement
2. **A defense optimization algorithm** that recommends segmentation and patching actions to minimize blast radius, compared against CVSS-ranked and random baselines
3. **Quantitative evaluation** on synthetic network topologies of varying size, measuring blast radius reduction, computational cost, and scalability
4. **(Stretch) A DSL** for defining network topologies and defense policies declaratively

## System Architecture

### Three-Layer Design

#### Layer 1: Network Model Builder

Takes raw input (network topology definitions, vulnerability scan data, or synthetic generators) and builds an attack graph. Nodes represent host-service pairs; directed edges represent possible lateral movement. Each edge carries a probability based on exploit complexity derived from CVSS metrics.

#### Layer 2: Attack Simulator

Runs Monte Carlo simulations on the attack graph. Starting from designated entry points (internet-facing hosts), the simulator probabilistically traverses edges, modeling attacker lateral movement. Produces a blast radius map: probability distribution of reachable assets per entry point.

Key metrics:
- **Expected blast radius** — mean reachable critical assets
- **Worst-case blast radius** — maximum reachable
- **Attack path depth** — average steps to critical assets

#### Layer 3: Defense Optimizer

Takes the blast radius map and recommends defensive actions:
- **Segmentation optimizer** — graph min-cut algorithms to identify connections to sever
- **Patch prioritizer** — greedy selection of vulnerabilities to patch based on blast radius reduction per patch

Outputs a ranked list of recommended actions with predicted blast radius reduction.

## Graph Model

### Node Types

- **Host-Service nodes** — e.g., `webserver01:apache-2.4.49`, `db01:mysql-8.0`
  - Properties: OS, service version, known CVEs (from NVD), network segment, criticality score
- **Entry point nodes** — markers for internet-facing services or initial access points

### Edge Types

- **Exploit edges** — "attacker on node A can exploit CVE-X to gain access to node B"
  - Properties: CVE ID, CVSS base score, exploit probability, required privilege level
- **Credential edges** — "access to node A implies credential access to node B" (shared credentials, LDAP trust)
- **Network reachability edges** — "node A can reach node B on port X" (prerequisites for exploit edges)

### Extensibility

Designed with typed nodes and edges from the start. Adding a privilege layer (user accounts, AD groups) later means adding new node/edge types without changing the simulation engine.

## Evaluation Methodology

### Synthetic Network Generation

Topologies of varying sizes:
- **Small:** 20-50 hosts
- **Medium:** 100-200 hosts
- **Large:** 500-1000 hosts

Each topology includes: network segments (DMZ, internal, database tier), realistic service distributions, and CVEs sampled from the actual NVD based on service types.

### Experiments

1. **Attack path validity** — Compare generated paths against MITRE ATT&CK technique chains. Metric: path plausibility score.
2. **Blast radius reduction** — For each network size, compare: no defense, CVSS-ranked patching, random patching, optimizer recommendations. Same defense budget across strategies. Metric: % blast radius reduction per defensive action.
3. **Scalability** — Computation time for simulation + optimization across network sizes. Metric: wall-clock time and memory usage.

### Statistical Analysis

- 1,000+ simulation runs per configuration
- Report: mean ± standard deviation, box plots
- Mann-Whitney U test for pairwise strategy comparisons (p < 0.05 threshold)
- Analysis in Python (scipy, matplotlib) via exported CSV from Elixir

### Baselines

- **CVSS-ranked patching** — fix highest-CVSS vulnerabilities first (industry standard)
- **Random defense** — apply defensive actions randomly (lower bound)
- **No defense** — full blast radius measurement (upper bound)

## Tech Stack

- **Elixir** — simulation engine (leveraging concurrency for Monte Carlo runs)
- **Phoenix LiveView** — visualization dashboard (attack graph, blast radius heat maps)
- **Mishka Chelekom** — UI component library for Phoenix
- **PostgreSQL** — primary database (graph model, simulation results)
- **TypeScript** — JS hooks for interactive graph visualization
- **Python** — statistical analysis (scipy, matplotlib, Jupyter notebooks)
- **NVD API** — real CVE data for realistic vulnerability assignment
- **(Stretch) OMeta-based DSL** — for declaring network topologies and defense policies

## Implementation Plan (Vertical Slices)

### Phase 1: Literature + Foundations (Months 1-2)

- Literature review: attack graphs (MulVAL, Ou et al.), blast radius concepts, defense optimization
- Define formal graph model (node/edge types, properties)
- Set up Elixir project structure, graph data structures
- Build synthetic network topology generator (small scale)

### Phase 2: Slice 1 — "Hello Attack Graph" (Month 3)

- Hardcoded tiny network (5 hosts, 3 segments)
- Simple graph construction, simple simulation (deterministic traversal)
- Basic Phoenix LiveView showing the graph + blast radius as colored nodes
- **End result:** Attack path lights up on screen

### Phase 3: Slice 2 — "Probabilistic + Defenses" (Months 4-5)

- Monte Carlo simulation (probabilistic traversal, 1000 runs)
- Add one defense strategy (greedy patch prioritizer)
- Visualization shows before/after blast radius comparison
- Synthetic topology generator (parameterized size)
- **End result:** Generate network → run simulation → apply defense → see difference visually

### Phase 4: Slice 3 — "Full Comparison" (Months 6-7)

- Add segmentation optimizer (min-cut)
- Add all baselines (CVSS-ranked, random, no-defense)
- Side-by-side comparison view in dashboard
- **End result:** Full tool working end-to-end, ready for experiments

### Phase 5: Evaluation (Months 8-9)

- Systematic experiments across network sizes (small/medium/large)
- Statistical analysis, charts, tables
- Scalability benchmarks

### Phase 6: Writing + Polish (Months 10-12)

- Thesis writing (introduction, related work, methodology, results, discussion)
- (Stretch) DSL for topology/policy definition
- (Stretch) Enhanced dashboard visualization
- Review, revision, defense preparation

## Key Literature to Review

- Sheyner et al. — Automated generation and analysis of attack graphs
- Ou et al. — MulVAL: A logic-based network security analyzer
- Noel & Jajodia — Attack graph analysis using network topology
- MITRE ATT&CK framework — technique chains for path validation
- CVSS v3.1 specification — for exploit probability derivation
