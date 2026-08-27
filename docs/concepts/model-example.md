# Model Example (Shared Synthetic Micro-Scenario)

This page is a stable, fictional reference example. It helps a reader apply the
model rules to one concrete set of nodes, relationships, and an attack path. It
is not an evaluated scenario, a code sample, or a deployment recipe.

The example uses two zones and two hosts. The client zone holds one client host.
The service zone holds one application host. The application host runs two
services, stores one credential, and supports one mission capability.

Use the canonical terms in [vocabulary.md](vocabulary.md). The model pages
define the semantics that make the path in this example valid.

## Nodes

The model uses six node types. This example uses all six.

| Node | Type | Value |
| --- | --- | --- |
| `client-zone` | `network_segment` | client zone |
| `service-zone` | `network_segment` | service zone |
| `client-01` | `host` | in `client-zone` |
| `app-01` | `host` | in `service-zone` |
| `orders` | `service` | TCP port `8080`, on `app-01` |
| `admin` | `service` | TCP port `8443`, administration, on `app-01` |
| `orders-rce` | `vulnerability` | on `orders`, grants user privilege |
| `deploy-cred` | `credential` | deployment credential |
| `order-processing` | `mission_capability` | supported by `app-01` |

## Relationships

The model uses seven authored relationship types. This example uses all seven.
Reachability is deny by default. The self-policy is explicit; same-zone
movement is not implicit.

| Relationship | From | To | Carries |
| --- | --- | --- | --- |
| `contains` | `client-zone` | `client-01` | - |
| `contains` | `service-zone` | `app-01` | - |
| `runs` | `app-01` | `orders` | - |
| `runs` | `app-01` | `admin` | - |
| `segment_reachability` | `client-zone` | `service-zone` | TCP `8080` |
| `segment_reachability` | `service-zone` | `service-zone` | TCP `8443` (self-policy) |
| `has_vulnerability` | `orders` | `orders-rce` | grants user |
| `stores_credential` | `app-01` | `deploy-cred` | required user |
| `authenticates_to` | `deploy-cred` | `admin` | grants administrator |
| `supports` | `app-01` | `order-processing` | - |

The `segment_reachability` edges authorize the `orders` and `admin` services.
They are policy, not measured flow. The `service-zone` self-policy exists
because same-zone access is not implicit. Without it, `admin` is not reachable.

## Attack path

The path has three steps. Each step is valid only when the previous step holds.

| Step | Action | Requires | Grants |
| --- | --- | --- | --- |
| 1 | Remote exploit of `orders` | foothold on `client-01`; reach `client-zone` to `orders`; exploit `orders-rce` | foothold on `app-01`; user privilege |
| 2 | Credential acquisition | user privilege meets required user for `deploy-cred` | ownership of `deploy-cred` |
| 3 | Credential reuse against `admin` | `deploy-cred`; reach `service-zone` self-policy to `admin` | administrator privilege |

The path is internally valid under the documented rules. Step 1 meets the
remote-exploitation rule: a foothold, directed reachability, a host running the
service, an applicable vulnerability, and an available attempt. Step 2 holds
because the attacker's user privilege meets the required user of
`deploy-cred`. Step 3 relies on the explicit `service-zone` self-policy; the
reused credential grants administrator privilege on `admin`.

## Mission capability

`order-processing` is supported by `app-01`. Its required flow is from
`client-zone` to the `orders` service. The capability is operational when that
flow exists, `app-01` is not compromised, and enough supporting hosts remain
uncompromised.

## Limits

Local exploitation is not shown. The path uses only remote service
exploitation and credential reuse. Vertical escalation through a local
vulnerability is out of scope for this example.
