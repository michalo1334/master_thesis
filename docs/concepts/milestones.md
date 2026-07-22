# Overview

Progress tracking: use cases mapped to milestones. Use case IDs reference `docs/concepts/usecases.md`.

# Milestone 1 — MVP (31.07.2026)

## Infrastructure

- [x] Basic project structure (src, docs, config, docker, etc.)
- [x] Telemetry & observability setup (Grafana, Tempo, Loki, Alloy)
- [x] UI dependencies (LiveSvelte, Bits UI, Svelte 5, Tailwind)
- [ ] CI/CD pipeline (precommit hooks, automated tests)

## 1. Model — Design Network Topology (all use cases)

- [x] Graph data model (Node, Edge, Graph schemas + adjacency list)
- [x] Graph persistence (CRUD via Graphs, optimistic locking, migrations)
- [x] Node types (Host, Service, Vulnerability with embedded validation)
- [x] Relationship types (NetworkReachability, Runs, HasVulnerability)
- [x] Graph query DSL (pattern matching with Query.match)
- [x] Graph diff engine (detect added/removed/changed nodes + edges)
- [x] Canvas rendering (SVG graph with pan, zoom, node/edge rendering)
- [x] Node management (add, remove, position by drag)
- [x] Edge management (connect mode, remove)
- [x] Object selection + inspectors (Host, Service, Vulnerability, Edge)
- [x] Force-directed layout with tunable parameters
- [x] Multi-document workspace (open/close/switch topologies)
- [x] Graph ↔ list view toggle

## 2. Simulate — Run Attack Simulation

- [x] Simulation engine core (Monte Carlo loop, iteration count, seeding)
- [x] Rule protocol + RemoteServiceExploitation rule
- [x] Action protocol + ExploitVulnerability action
- [x] Attacker state tracking (footholds, attempted actions)
- [x] Single and multi-run simulation (run/run_multiple)
- [x] Dashboard integration (trigger simulation from ribbon)
- [ ] Simulation parameter configuration UI (seed, iteration count)

## 3. Analyze — Examine Results

- [x] Simulation report component (SimulationReport.svelte)
- [x] KPI cards component (KpiCards.svelte)
- [x] Statistical chart component (StatisticalChart.svelte)
- [ ] Blast radius heat map on graph nodes
- [x] Data pipeline: simulation results → dashboard UI
- [ ] Compromised host/attack path inspection

## 4. Defend — Optimize & Apply Defenses

- [ ] Optimizer core stub (empty file)
- [ ] Patch vulnerability action stub
- [ ] Block reachability action stub

## Thesis

- [x] Skeleton (LaTeX template, class file)
- [ ] Chapter — introduction
- [x] Chapter — literature review
- [ ] Chapter — design
- [ ] Chapter — implementation

# Milestone 2 — Core simulation + analysis pipeline (15.08.2026)

## Infrastructure

- [ ] IaC — Terraform local dev environment
- [ ] IaC — Terraform Azure dev environment

## 2. Simulate — Run Attack Simulation

- [x] Trigger simulation from dashboard
- [ ] Configure simulation parameters via UI
- [ ] Telemetry inside simulator (OTel spans)
- [ ] Simulation progress indicator

## 3. Analyze — Examine Results

- [ ] Blast radius heat map (node coloring by compromise probability)
- [ ] Data pipeline: connect simulation output to dashboard
- [ ] Compromised host list (which hosts reached, how often)
- [ ] Attack path visualization (highlighted edges)
- [ ] Simulation report with KPIs + charts

## 4. Defend — Optimize & Apply Defenses

- [ ] Greedy defense optimizer
- [ ] Simulate-only defense evaluation (hypothetical what-if)

## 5. Verify — Re-simulate After Defense

- [ ] Re-simulation after applying/hypothesizing a defense
- [ ] Before/after comparison UI (side-by-side KPIs)

## 6. Report — Export Results

- [ ] Export simulation statistics to CSV

## External data

- [ ] CVE/CVSS API fetch (NVD API integration)

## Thesis

- [ ] Chapter — design, implementation
- [ ] Chapter — evaluation
- [ ] Chapter — conclusion

# Milestone 3 — Full evaluation + thesis (30.09.2026)

## 4. Defend — Advanced

- [ ] Apply patch vulnerability on a service
- [ ] Apply block reachability between two nodes
- [ ] Compare predicted vs actual blast radius reduction

## 6. Report — Export

- [ ] Export thesis evaluation dataset (parameter sweeps, topology variants)

## Thesis

- [ ] Complete thesis document
- [ ] Final review and submission preparation
