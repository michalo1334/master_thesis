# Enterprise Network Topology Sources

Research on sources that can inform stylized enterprise network layouts (~100--500 hosts) for future thesis scenarios. Target: networks described in terms of hosts, services, vulnerabilities, and reachability --- not routing/device-level topologies. The current evaluation scope remains one fixed stylized topology, policy, and attacker model.

Status: published machine-readable enterprise network topologies at 100+ host scale essentially do not exist. Organizations don't publish internal network maps. The standard approach in attack-graph literature (NetSPA, MulVAL, TVA) is parameterized synthetic generation informed by real structural patterns.

---

## Directly Available Sources

### 1. GOAD — Game of Active Directory

**Repository:** `github.com/Orange-Cyberdefense/GOAD` — 8.1k stars, actively maintained

Full lab: 5 VMs, 2 forests, 3 domains. Published topology diagram with explicit host roles and services. Ansible playbooks in `ad/` directory define every service installed on every VM. Documented vulnerabilities and attack paths.

Available lab variants:
- **GOAD** (full): 5 VMs, 2 forests, 3 domains
- **GOAD-Light**: 3 VMs, 1 forest, 2 domains
- **SCCM**: 4 VMs with Microsoft Configuration Manager
- **MINILAB**: 2 VMs, basic domain

What to extract:
- Host names, roles, domain membership, OS versions
- Service inventory per host (IIS, MSSQL, SMB, RDP, WinRM, LDAP, Kerberos, DNS, DHCP)
- Reachability: which zones can contact which services
- AD trust relationships as credential edges
- Known vulnerable configurations (AS-REP roasting, Kerberoasting, unconstrained delegation, etc.)

How to scale: parameterize the branch-office pattern — each branch gets DC, file server, workstations.

### 2. DetectionLab

**Repository:** `github.com/clong/DetectionLab` — 5k stars, archived since 2023

4 VMs: DC, WEF server, Win10 workstation, Logger. Vagrantfiles and Ansible playbooks define all services. Heavier on security monitoring infrastructure (Splunk forwarder, Sysmon, osquery, Suricata, Zeek, Windows Event Forwarding).

What to extract:
- Enterprise services: Active Directory, DNS, DHCP, SMB shares, RDP
- Monitoring infrastructure as additional hosts/services
- GPO-based configurations that affect security posture
- Network segmentation between management, logging, and production

### 3. AutomatedLab

**Repository:** `github.com/AutomatedLab/AutomatedLab` — 2.2k stars

PowerShell provisioning framework with predefined lab templates for multi-domain forests, Exchange, PKI, IIS farms, SQL clusters, ADFS. Lab definitions include machine counts, roles, and network segmentation.

Available lab templates:
- Multi-domain Active Directory forests with trust relationships
- Exchange Server topologies (single/multi-server)
- PKI/ADCS hierarchies (root CA, issuing CA)
- SQL Server Always-On clusters
- IIS web farms
- ADFS/WAP scenarios

What to extract: the role-to-machine mappings define realistic service distribution patterns.

---

## Academic & Research Sources

### 4. Attack-Graph Literature Evaluation Networks

Papers cited in the thesis bibliography used known but not openly published networks. However:

**MulVAL** (`github.com/risksense/mulval` — archived): example input files with Datalog facts describing hosts, services, vulnerabilities, and reachability. These are small (dozens of hosts) but provide a complete fact pattern that can be scaled.

**NetSPA** (Homer et al., cited in `thesis/refs.bib`): evaluated on government and enterprise networks with hundreds to thousands of hosts. The papers describe the network characteristics (subnet structure, service distribution, vulnerability density) even though they don't publish the raw data.

**MulVAL/NetSPA topology pattern**: networks are described as facts — `networkServiceInfo(host, service, protocol, port)`, `vulExists(host, vulID, program)`, `hacl(src, dst, protocol, port)` — which maps to your graph model as Host, Service, and Vulnerability nodes with `Contains` and `Runs` edges. `hacl` facts become `SegmentReachability` policy rules between segments; the materializer derives the operational `Host -> Service` flow from the policy. See `../plans/reachability-modeling.md`.

### 5. CIC Datasets (Canadian Institute for Cybersecurity, UNB)

**URL:** `unb.ca/cic/datasets`

CSE-CIC-IDS2018: multi-segment enterprise network with specific architecture documented in the dataset paper. 5 departments, 500+ machines, specific server roles (web server, DNS, Active Directory, file server, database), attack scenarios from the internal network. The network architecture diagram and machine role distribution are published; individual machines are not enumerated but described by role distribution.

Other relevant CIC datasets: CIC-IDS2017 provides a smaller but well-documented enterprise testbed.

### 6. MITRE ATT&CK Evaluations — Target Environments

**URL:** `attack.mitre.org/evaluations/`

Each evaluation round defines a target enterprise network. For example, the 2023 Turla evaluation documents a multi-subnet environment with domain structure, Linux and Windows hosts, specific software configurations, and network segmentation. The environment descriptions are published in the evaluation methodology documents.

Not published as topology files — must be reverse-engineered from the textual description.

---

## Reference Architectures (Structural Patterns, Not Datasets)

These describe how real enterprises structure networks. Use them to inform synthetic topology design, not to validate the model against real attack behavior.

### 7. Microsoft Enterprise-Scale Landing Zones

**URL:** `learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/`

Reference architecture with hub-spoke topology, DMZ, internal zones, management plane, identity subscription. Describes:
- Network segmentation patterns (hub VNet, spoke VNets, Azure Firewall)
- Identity architecture (Active Directory, Entra ID sync)
- Management/monitoring separation
- Connectivity patterns between zones

### 8. CIS Benchmarks / Security Templates

Center for Internet Security publishes benchmark documents for enterprise services (Windows Server, IIS, SQL Server, etc.). While these are security configuration guides, they implicitly describe what services exist in enterprise deployments and how they interrelate.

### 9. MITRE ATT&CK — Enterprise Matrix

**URL:** `attack.mitre.org/matrices/enterprise/`

Documents the techniques real attackers use. The prerequisite relationships between techniques (e.g., "Valid Accounts → Remote Services → Lateral Tool Transfer") imply the graph structures that need to exist: credential reuse requires `StoresCredential`/`AuthenticatesTo` edges and traverses the operational graph; remote services exploitation requires segment containment plus a `SegmentReachability` policy rule, from which materialization derives only `NetworkReachability`; the canonical `Runs` and `HasVulnerability` relationships are then traversed with it. Direct `HasCredential` or host/service reachability mappings are superseded by `../plans/reachability-modeling.md`.

---

## What Does NOT Exist (and Will Not)

- A JSON/YAML file describing a real 200-host enterprise with service inventory per host
- Published firewall rule sets from production networks
- Real organization network diagrams with machine-count annotations
- Open datasets from security audits or penetration tests (for obvious reasons)

The closest thing to a real published topology is the GOAD Ansible inventory — but at 5 VMs, it's too small for your thesis experiments.

---

## Practical Recommendation: Parameterized Synthetic Generator

### Step 1: Extract Enterprise Patterns from Available Sources

| Pattern | Source | Structural Elements |
|---------|--------|---------------------|
| Domain controller topology | GOAD, AutomatedLab | Primary DC, backup DC, forest trust, AD-integrated DNS |
| DMZ structure | DetectionLab, CIC, Microsoft LZ | Reverse proxy / IIS, public web server, no direct DB access from internet, separate subnet |
| Internal service distribution | GOAD Ansible, AutomatedLab | File servers (SMB/NFS), DB servers (MSSQL/MySQL/PostgreSQL), Exchange, IIS/Apache, RDP, SSH, LDAP, Kerberos |
| Admin workstation separation | GOAD, AutomatedLab | Jump hosts / PAWs, separate management VLAN, restricted RDP from user VLAN |
| CI/CD pipeline | Enterprise reference architectures | Git server, CI runner (Jenkins/GitHub Actions), artifact repository (Nexus/Artifactory), deployment targets |
| Backup infrastructure | AutomatedLab, DetectionLab | Backup server (Veeam/CommVault), isolated backup network segment |
| Identity services | GOAD, AutomatedLab | AD DS, ADFS, Azure AD Connect, RADIUS/NPS, PKI/ADCS |
| Monitoring / SOC | DetectionLab | SIEM (Splunk/ELK), EDR agents, syslog aggregation, NIDS (Suricata/Zeek) |

### Step 2: Build a Parameterized Graph Generator

Write a generator (Elixir or Python script) that takes parameters:
- `num_segments`: number of network zones (DMZ, internal, management, backup, user)
- `hosts_per_segment`: machine count distribution per zone
- `service_density`: how many services per host on average
- `vulnerability_density`: how many CVEs per service on average
- `reachability_rules`: which zones can reach which services
- `seed`: deterministic random seed for reproducibility

Output: JSON matching your `GraphContract` schema — nodes and edges ready to load into the system.

Constraints to enforce:
- DMZ hosts cannot reach internal databases directly
- Management VLAN is separate from user VLAN
- Jump hosts required for admin access to production
- Backup segment is isolated except from backup server
- Internet-facing endpoints are in DMZ only

### Step 3: Seed Vulnerability Data from NVD

For each generated host running a known service (e.g., Apache 2.4.49, OpenSSH 8.2):
1. Query NVD API for CVEs affecting that product+version combination
2. Preserve CVSS data as vulnerability severity characteristics
3. Assign `exploit_probability` separately as a documented, stylized scenario parameter; do not derive it from CVSS or present it as real-world exploit likelihood
4. Apply version distribution skew — not all hosts run latest patches

### Step 4: Check Structural Coverage Against Documented Attack Patterns

Before using a generated topology in experiments, check whether selected documented technique chains have plausible paths through it. This is a structural check, not validation of real attacker behavior:

1. Pick 3-4 documented attack chains from CTID/CALDERA adversary emulation plans (e.g., APT29 — spearphishing → credential theft → lateral movement → data exfiltration)
2. Map each step to your graph model: what host is entry point, what segment policy rules enable lateral movement, what vulnerabilities are exploitable
3. If a generated topology doesn't have plausible paths, adjust generation parameters

### Step 5: Document the Scenario Rationale

In the thesis evaluation chapter, justify the synthetic approach:

> Synthetic topologies are common in attack-graph literature. NetSPA (Homer et al., 2009), MulVAL (Ou et al., 2005), and TVA (Ammann et al., 2002) use generated networks rather than published production topologies. The current thesis scope uses one fixed stylized scenario. Future parameter sweeps require a versioned runner and result artifacts before reporting sensitivity or scalability. Structural patterns may be informed by open training environments, enterprise reference architectures, and documented attack-graph evaluation networks.

---

## Summary

| Source | Scale | Machine-Readable? | Svc/Vuln Data? | Best Use |
|--------|-------|--------------------|----------------|----------|
| GOAD | 2–5 VMs | Yes (Ansible) | Yes (documented) | Extract structural patterns |
| DetectionLab | 4 VMs | Yes (Ansible) | Yes (documented) | Extract monitoring infrastructure patterns |
| AutomatedLab | Parametric | Yes (PowerShell) | Yes (roles) | Extract multi-domain forest patterns |
| MulVAL examples | ~20 hosts | Yes (Datalog facts) | Yes (CVE IDs) | Extract fact-format topology patterns |
| CIC-IDS2018 | ~500 machines | No (role dist. only) | Limited (attack labels) | Validate segment design |
| MITRE ATT&CK Evals | ~50-100 hosts | No (textual) | Yes (software list) | Validate attack chain plausibility |
| Microsoft LZ | Reference N/A | No (diagrams) | No | Validate network segmentation design |
| Real enterprise topologies at 100+ scale | — | — | — | **Do not exist publicly** |
