# Unified Plan: Master Thesis + Work Growth Project

> **Superseded.** This plan describes the earlier host/service reachability model and min-cut segmentation. The canonical model — segment-to-segment policy with a deterministic in-memory operational projection — is defined in [Reachability Modeling — Canonical Policy, Transient Operational Flows](../plans/reachability-modeling.md). Historical record only.

## Vision

A **single-pane-of-glass security platform** that:

1. **Models** network infrastructure as a live attack graph (real nodes, synthetic nodes, or both)
2. **Simulates** attacker propagation via Monte Carlo to measure blast radius
3. **Recommends** and **applies** defensive actions to minimize blast radius
4. **Validates** defense effectiveness through continuous live observation

This system serves as:
- **Master thesis deliverable** — graph-based attack simulation with quantitative evaluation
- **Work growth project deliverable** — security testing platform for self-hosted infrastructure
- **Personal tool** — fast-iteration security dashboard for managing network defenses

---

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Phoenix LiveView Dashboard                       │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐    │
│  │ Attack Graph  │  │ Blast Radius │  │ Defense Recommendations│    │
│  │ Visualization │  │ Heat Map     │  │ + Apply Controls       │    │
│  │ 🟢 live nodes │  │ before/after │  │ [Apply] [Simulate]     │    │
│  │ 🔵 synthetic  │  │              │  │ [Dismiss] [Export]     │    │
│  └──────────────┘  └──────────────┘  └────────────────────────┘    │
└────────────────────────────┬────────────────────────────────────────┘
                             │ LiveView PubSub
┌────────────────────────────┼────────────────────────────────────────┐
│                     Core Engine (Elixir/OTP)                        │
│                             │                                       │
│  ┌──────────────────────────┴──────────────────────────────────┐    │
│  │              Unified Attack Graph (ETS/GenServer)           │    │
│  │                                                             │    │
│  │   Nodes: %{id, source, host, services, cves, segment}      │    │
│  │   Edges: %{from, to, type, probability, cve_id}            │    │
│  │                                                             │    │
│  │   source = :live | :synthetic  (graph is source-agnostic)   │    │
│  └──────┬─────────────────────┬────────────────────┬───────────┘    │
│         │                     │                    │                │
│  ┌──────┴──────┐  ┌──────────┴─────────┐  ┌──────┴──────────┐     │
│  │ Layer 1     │  │ Layer 2            │  │ Layer 3          │     │
│  │ Model       │  │ Simulator          │  │ Optimizer        │     │
│  │ Builder     │  │                    │  │                  │     │
│  │ - live obs. │  │ - Monte Carlo      │  │ - Min-cut segm. │     │
│  │ - synthetic │  │ - blast radius map │  │ - Greedy patch   │     │
│  │ - nmap XML  │  │ - entry point scan │  │ - Hybrid         │     │
│  └──────┬──────┘  └────────────────────┘  └──────────────────┘     │
│         │                                                           │
└─────────┼───────────────────────────────────────────────────────────┘
          │
          │ Two input channels (produce identical node/edge structures)
          │
     ┌────┴────────────────────────────────────────┐
     │                                              │
     ▼                                              ▼
┌─────────────────────┐              ┌──────────────────────────┐
│  Live Observers     │              │  Synthetic Generator     │
│                     │              │                          │
│  Lightweight agents │              │  Parameterized topology  │
│  on real servers    │              │  generator               │
│  - periodic scan    │              │  - size, segments        │
│  - services/ports   │              │  - vuln density          │
│  - pkg versions     │              │  - CVE sampling from NVD │
│  - firewall state   │              │                          │
│  Reports diffs only │              │  One-shot or on-demand   │
└──────┬──────────────┘              └──────────────────────────┘
       │ observes
       ▼
┌─────────────────────────────────────────────────────────────┐
│                Physical/Virtual Infrastructure              │
│                                                             │
│  ┌─── DMZ ────────┐  ┌─── Internal ───┐  ┌── DB Tier ──┐  │
│  │ 🟢 web01       │  │ 🟢 app01       │  │ 🟢 db01     │  │
│  │    nginx 1.16  │  │    node.js 14  │  │    mysql 5.7│  │
│  │ 🟢 web02       │  │ 🟢 jump01      │  │ 🟢 redis 6  │  │
│  │    apache 2.4  │  │    ssh/vpn     │  │             │  │
│  └────────────────┘  └────────────────┘  └─────────────┘  │
│                                                             │
│  Running on: libvirt VMs → later thin clients/hardware      │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow: Server State Change → Dashboard Update

```
1. web01 gets patched (nginx 1.16 → 1.25)
   │
   ▼
2. Observer on web01 detects version change
   │  (periodic: check dpkg/rpm versions every 60s)
   │
   ▼
3. Observer sends diff to central:
   │  {:node_update, "web01", %{services: [%{name: "nginx", version: "1.25.0"}]}}
   │
   ▼
4. Model Builder receives update:
   │  - Looks up CVEs for nginx 1.25.0 in NVD cache
   │  - Old CVEs (for 1.16.0) no longer apply → remove exploit edges
   │  - New CVEs (if any) → add new exploit edges
   │  - Mutates the unified attack graph
   │
   ▼
5. Graph mutation triggers simulation re-run (debounced):
   │  - Monte Carlo runs
   │  - New blast radius map computed
   │
   ▼
6. LiveView receives PubSub update:
   │  - Attack graph re-renders (removed edges disappear)
   │  - Blast radius heat map updates
   │  - Dashboard shows: "Blast radius reduced by 23%"
   │
   ▼
7. You see the effect of your patch in real-time 🎯
```

### Defense Application Flow (from GUI)

```
Dashboard recommendation:
  "Segment db01 from DMZ (min-cut: sever web01 → db01 edge)"
  [Apply] [Simulate Only] [Dismiss]

  [Simulate Only] → Re-run Monte Carlo with edge hypothetically removed
                    Show predicted blast radius reduction (no real change)

  [Apply] → Send command to observer on web01/db01:
             {:apply_defense, :firewall_rule,
               %{block: "db01:3306", from: "dmz_segment"}}
             → Observer executes iptables rule
             → Observer reports new state
             → Graph updates → simulation re-runs → LiveView updates
             → Dashboard: "Applied. Actual reduction: 21%. Predicted: 23%."

  [Dismiss] → Log decision, move to next recommendation
```

### Hybrid Topology: Real + Synthetic

```
┌─────────────────────────────────────────────────────────────┐
│                    Unified Attack Graph                       │
│                                                               │
│  Real lab (6 nodes):                Synthetic expansion:      │
│  ┌─────┐  ┌─────┐  ┌─────┐        ┌─────┐  ┌─────┐         │
│  │web01│─▶│app01│─▶│db01 │───────▶│sim01│─▶│sim02│         │
│  │ 🟢  │  │ 🟢  │  │ 🟢  │        │ 🔵  │  │ 🔵  │         │
│  └──┬──┘  └──┬──┘  └─────┘        └──┬──┘  └─────┘         │
│     │        │                        │                       │
│  ┌──┴──┐  ┌──┴──┐  ┌─────┐        ┌──┴──┐  ┌─────┐         │
│  │web02│  │jump │  │db02 │        │sim03│─▶│sim04│  ···     │
│  │ 🟢  │  │ 🟢  │  │ 🟢  │        │ 🔵  │  │ 🔵  │         │
│  └─────┘  └─────┘  └─────┘        └─────┘  └─────┘         │
│                                                               │
│  🟢 = live observed     🔵 = synthetically generated          │
│  Real↔synthetic edges generated based on segment rules        │
└─────────────────────────────────────────────────────────────┘

Use case: "I have 6 real servers. What happens at 100 nodes?"
          → Add 94 synthetic nodes → simulate at scale
          → Validates scalability (thesis sub-question #3)
```

---

## Graph Model

### Node Structure

```elixir
%Node{
  id: "web01",
  source: :live | :synthetic,
  hostname: "web01",
  os: "Ubuntu 20.04",
  segment: :dmz | :internal | :database,
  criticality: 0.0..1.0,
  services: [
    %Service{name: "nginx", version: "1.16.0", port: 80, cves: ["CVE-2019-9511"]}
  ],
  observer_pid: pid | nil   # nil for synthetic nodes
}
```

### Edge Types

- **Exploit edge** — "attacker on A can exploit CVE-X to reach B"
  - Properties: cve_id, cvss_score, exploit_probability, required_privilege
- **Credential edge** — "access to A implies credential access to B" (shared passwords, LDAP)
- **Network reachability edge** — "A can reach B on port X" (prerequisite for exploit edges)

### Source Agnosticism

The simulation engine treats all nodes identically regardless of source. The only difference:
- `:live` nodes have an `observer_pid` — they receive state updates and defense commands
- `:synthetic` nodes have static properties set at generation time

---

## Lab Topology (Self-Hosted Environment)

### Target Services (intentionally vulnerable versions)

| Segment | Host | Service | Vulnerable Version | Key CVEs | Purpose |
|---------|------|---------|-------------------|----------|---------|
| DMZ | web01 | nginx | 1.16.0 | CVE-2019-9511, CVE-2019-9513 (HTTP/2 DoS) | Web frontend |
| DMZ | web02 | Apache httpd | 2.4.49 | CVE-2021-41773 (path traversal → RCE 🔥) | Shows dramatic blast radius change on patch |
| Internal | app01 | Node.js 14 + Express | 14.x with vuln deps | Various npm CVEs | App tier |
| Internal | app02 | PHP 7.4 + WordPress | 5.7 | Multiple WP CVEs | Tests greedy patch prioritization |
| Internal | jump01 | OpenSSH | Latest but with password auth | Brute force vector | Tests credential edge removal |
| Database | db01 | MySQL | 5.7 | CVE-2020-14812 etc. | Database tier |
| Database | db02 | Redis | 6.0 (no auth!) | Unauthorized access 🔥 | Shows lateral movement via credential edges |

### Infrastructure Progression

1. **Now:** All VMs via libvirt/KVM on main machine (i5 14th gen, 42GB RAM)
2. **Later (optional):** Move DMZ nodes to thin client #1, jump box to thin client #2
3. **Hybrid:** Mix of VMs and physical nodes — graph doesn't care

### Networking

- Virtual bridges per segment (br-dmz, br-internal, br-database)
- iptables rules between bridges = firewall/segmentation
- VPN (WireGuard or OpenVPN) on jump01 for external access testing

---

## Work Growth Project: Deliverable Mapping

### Required Deliverables → Tool Capabilities

| Work Deliverable | How the Tool Delivers It |
|---|---|
| Security test scenarios (port scanning, error forcing, VPN bypass) | Attack graph paths = test scenarios. Each path is auto-generated from topology. |
| Results report | Dashboard exports: blast radius maps, attack paths, vulnerability lists, before/after comparison |
| Hardening implementations (passwords, IP restrictions, headers, firewall) | Click [Apply] in dashboard → tool pushes configs to nodes via observers |
| Re-tests showing improvement | Automatic: after applying defense → observers detect change → simulation re-runs → dashboard shows improvement |

### Skills Acquired

| Required Skill | How Acquired |
|---|---|
| Security basics in self-hosted environments | Building and managing the lab infrastructure |
| Practical use of security testing tools | Integrating nmap/OpenVAS output, using the dashboard |
| Scan/log analysis | Tool visualizes scan results as attack graphs |
| Designing and verifying security fixes | Optimizer recommends fixes, live observers confirm effectiveness |

---

## Phased Implementation Plan

### Phase 1: Foundations

**Thesis focus:** Literature review, formal graph model, Elixir project setup
**Work focus:** Set up libvirt lab with first few VMs
**Shared:** Define the Node/Edge data structures that work for both live and synthetic sources

Deliverables:
- Literature review document (attack graphs, blast radius, defense optimization)
- Elixir project scaffold (Phoenix LiveView, PostgreSQL, Mishka Chelekom)
- Graph data structures (source-agnostic nodes and edges)
- First libvirt VMs running (web01 + db01 minimum)

### Phase 2: "Hello Attack Graph" — First Vertical Slice

**Thesis focus:** Hardcoded tiny network, basic simulation, LiveView visualization
**Work focus:** Deploy remaining lab VMs, install services at vulnerable versions
**Shared:** The first visualization shows your actual lab topology

Deliverables:
- Tiny attack graph (hardcoded or from lab) renders in LiveView
- Basic deterministic traversal simulation
- Attack paths light up on screen
- Lab has all 6-7 VMs running with vulnerable services

### Phase 3: Live Observers + Probabilistic Simulation

**Thesis focus:** Monte Carlo simulation, greedy patch prioritizer, before/after viz
**Work focus:** Build observer agents, initial security assessment of lab
**Shared:** Observers feed live data into the same graph the simulator uses

Deliverables:
- Lightweight observer daemon deployable to lab nodes
- Live nodes appear in graph with real service/CVE data
- Monte Carlo simulation runs on live topology
- Synthetic generator produces parameterized topologies
- First defense recommendation + before/after comparison
- Initial security assessment data collected for work project

### Phase 4: Full Defense Optimization + Work Report

**Thesis focus:** Min-cut segmentation, all baselines, side-by-side dashboard
**Work focus:** Apply hardening, re-test, write employer report
**Shared:** Dashboard is the single pane of glass for both

Deliverables:
- Min-cut segmentation optimizer
- CVSS-ranked, random, and no-defense baselines
- Side-by-side comparison view
- [Apply] button pushes defenses to live nodes
- Before/after data for work project report
- Work growth project report delivered to employer (mid-year checkpoint)

### Phase 5: Systematic Evaluation

**Thesis focus:** Experiments on synthetic topologies (20-1000 hosts) + real-world case study
**Work focus:** Done ✅

Deliverables:
- Synthetic experiments across small/medium/large networks
- Case study: real lab topology (before/after hardening, predicted vs actual)
- Hybrid experiments: real + synthetic nodes at scale
- Statistical analysis (Mann-Whitney U, box plots, tables)
- Scalability benchmarks

### Phase 6: Thesis Writing + Polish

**Thesis focus:** LaTeX writing, defense preparation
**Work focus:** Done ✅

Deliverables:
- Complete thesis document
- Case study chapter using work project data
- (Stretch) Enhanced visualization, topology DSL
- Defense presentation

---

## Tech Stack

| Component | Technology |
|---|---|
| Backend/Engine | Elixir + Phoenix 1.8 |
| Frontend | Phoenix LiveView + Mishka Chelekom UI |
| Graph Viz | TypeScript hooks (D3.js or Cytoscape.js) |
| Database | PostgreSQL (graph model, simulation results) |
| Infrastructure | libvirt/KVM VMs → later thin clients |
| Networking | Virtual bridges, iptables, WireGuard/OpenVPN |
| Observers | Lightweight Elixir agents or shell+cron daemons |
| CVE Data | NVD API (real CVE data for services) |
| Thesis | LaTeX (university template) |
| Statistics | Python (scipy, matplotlib, Jupyter) |

---

## Key Design Decisions

1. **Source-agnostic graph**: Nodes don't know or care if they're backed by real or synthetic infrastructure. This enables mix-and-match and clean evaluation methodology.

2. **Observers report diffs, not full state**: Minimizes network traffic and enables debounced simulation re-runs.

3. **Defense application is optional**: The tool always works as a pure simulator. [Apply] is an extra capability for live nodes. This keeps the thesis evaluation clean (synthetic experiments don't have apply capability).

4. **Thesis proposal stays as-is**: The hybrid architecture is an enhancement, not a scope change. The core research question and evaluation methodology are unchanged. If the live/hybrid features don't work out, the thesis still stands on synthetic evaluation alone.

5. **Work project is not blocked on thesis tool**: Lab setup and manual security testing can proceed independently. The tool integration is additive — makes the work project better, but isn't required for it.

---

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Scope creep from hybrid architecture | Keep synthetic-only as the baseline. Live observers are a bonus, not a requirement. |
| Observer security (agents with sudo access) | Lab is isolated. In thesis, discuss security implications as future work. |
| NVD API rate limits | Cache CVE data locally. Refresh periodically, not per-query. |
| Libvirt resource contention on daily machine | Set VM memory limits. Pause VMs when not testing. |
| Supervisor concerns about expanded scope | Don't update proposal. Deliver more than promised. |

---

## Success Criteria

### Thesis
- [ ] Attack graph model correctly represents network topologies
- [ ] Monte Carlo simulation produces stable blast radius estimates
- [ ] Defense optimizer measurably reduces blast radius vs baselines
- [ ] Evaluation on 3 synthetic network sizes with statistical significance
- [ ] (Bonus) Case study on real lab topology validates model fidelity

### Work Growth Project
- [ ] Self-hosted lab built and operational
- [ ] Security test scenarios documented and executed
- [ ] At least 5 hardening improvements implemented
- [ ] Before/after comparison shows measurable improvement
- [ ] Skills report demonstrates acquired competencies

### Personal Tool
- [ ] Dashboard provides single-pane-of-glass view of network security posture
- [ ] Can iterate on defenses quickly through the GUI
- [ ] Supports both real and synthetic nodes seamlessly
