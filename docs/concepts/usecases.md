# Use cases

Grouped by workflow stage. Actor: security analyst / researcher.

Status: `[x]` = code exists, `[ ]` = not started

## 1. Model — Design Network Topology

- [x] Create new graph
- [x] Open existing graph from database
- [x] Close active graph
- [x] Manage nodes
    - [x] Add host node
    - [x] Add service node
    - [x] Add vulnerability node
    - [x] Add network segment node
    - [x] Remove node
    - [x] Position node by dragging on canvas
- [x] Manage edges
    - [x] Connect network segments (SegmentReachability policy edge)
    - [x] Connect service to host (Runs edge)
    - [x] Connect vulnerability to service (HasVulnerability edge)
    - [x] Remove edge
- [x] Select node or edge on canvas
- [x] Inspect node properties
    - [x] Host inspector (name)
    - [x] Service inspector (name, protocol, port, version)
    - [x] Vulnerability inspector (identifier, CVSS score, exploit probability)
- [x] Inspect edge properties
    - [x] Segment reachability policy inspector (protocol, port range)
    - [x] Generic canvas edge inspector (from, to, type)
- [x] Apply force-directed layout
    - [x] Tune layout parameters (repulsion, link distance, collision radius, gravity, alpha decay)
- [x] Save graph to database with base-revision conflict rejection
- [x] Switch between multiple open topologies (document tabs, workspace)
- [x] Toggle between Topology and Network views

## 2. Simulate — Run Attack Simulation

- [x] Run single simulation (N iterations of rule-based action selection)
- [x] Run multiple simulations (M runs × N iterations — Monte Carlo ensemble)
- [x] Configure simulation parameters (seed, iteration count) via UI
- [x] Trigger simulation from dashboard

## 3. Analyze — Examine Results

- [ ] View blast radius distribution on graph nodes (color-coded heat map)
- [x] View simulation KPIs (expected blast radius, min/max, percentiles)
- [x] View statistical charts (histograms, distributions)
- [x] Inspect compromised hosts
- [x] Inspect attack paths (edges traversed)
- [x] View simulation report

## 4. Defend — Optimize & Apply Defenses

- [x] Run defense optimizer (greedy strategy)
- [ ] Apply patch vulnerability on a service
- [ ] Apply segmentation (remove a segment reachability policy)
- [ ] Compare predicted vs actual blast radius reduction

## 5. Verify — Re-simulate After Defense

- [ ] Re-run simulation after applying a defense action
- [ ] Compare blast radius before and after (side-by-side)

## 6. Report — Export Results

- [ ] Export simulation statistics to CSV
- [ ] Export thesis evaluation dataset (parameter sweeps, topology variants)
