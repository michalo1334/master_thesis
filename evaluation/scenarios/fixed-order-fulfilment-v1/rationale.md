# Scenario Rationale

This scenario is synthetic and fixed. It tests modeled behavior. It does not
measure real enterprise effectiveness.

The organization and business names are fictional. They avoid implying a real
enterprise. The product versions and CVE identifiers are real. The local
reviewed NVD subset maps them.

Segment policies represent logical enforcement. Gateway and bastion systems
are hosts. Attack rules act on their services. Router and firewall node types
are out of scope.

The structure covers five parts:

- a public-service entry point
- credential reuse
- identity access
- management separation
- a protected business route

These concepts follow:

- [Topology source research](../../../docs/concepts/enterprise-topology-sources.md)
- [NIST SP 800-207](https://csrc.nist.gov/pubs/sp/800/207/final)
- [MITRE ATT&CK T1190](https://attack.mitre.org/techniques/T1190/)
- [MITRE ATT&CK T1021](https://attack.mitre.org/techniques/T1021/)

CVSS characteristics and exploit probabilities remain separate. This keeps
each measure independent.

The local NVD files are static input. No evaluation run contacts NVD. The
snapshot is frozen at the reviewed revision.

The graph fixes two attacker contexts. Each context has its own evaluation
manifest. `fixed-order-fulfilment-v1` starts at `internet-entry` and proves the
severity-versus-mission control. `fixed-order-fulfilment-feasibility-v1` starts
at `order-gateway` and proves the blast-radius-versus-feasibility control. The
two manifests share this graph. Do not compare results across attacker
footholds. Each manifest's effect estimate is valid only within its own
starting context.

A result archive records its exact graph. Fresh database runs do not yet
claim graph-identity equality. The UUID limits identity claims.

This rationale explains design intent. It does not restate host inventory or
graph structure that the scenario builder already defines.
