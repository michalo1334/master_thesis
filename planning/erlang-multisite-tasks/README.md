# Multi-Site Implementation States

The approved design is in `../erlang-multisite-design-draft.md`. Execute these
state files in numeric order. Each file describes one 1-2 hour change that ends
with an applicable, health-checked stack. Do not start the next state until the
current state passes its review and working-state gate.

## Change legend

Incremental C4 diagrams use these colors:

| Color | Meaning |
|---|---|
| Green | Added or enabled in this state |
| Amber | Changed, rewired, or verified in this state |
| Red | Removed in this state; a red element is a change annotation, not an end-state resource |
| Grey | Present and intentionally unchanged |

Terraform trees use these markers:

| Marker | Meaning |
|---|---|
| `+` | Add |
| `~` | Change |
| `-` | Remove |
| `!` | Intentional destroy or replacement |
| `=` | Keep unchanged |

## Working-state rule

A state is complete only when Terraform can apply it from the previous state,
all retained long-running containers are healthy, each one-shot container exits
zero, and documented outputs describe only available entry points. A feature can
be intentionally absent when the state file says so. Hidden half-configuration
is not a working state.

Health checks and Terraform provider waits are the runtime acceptance mechanism.
Static checks and existing project tests still run when a state changes their
code. Do not add smoke-test frameworks or metric-specific test suites.

## Availability by state

| State | Sites | PubSub | Analysis | Observability | App metrics |
|---|---:|---|---|---|---|
| Current | 1 | PG2 | One host-exposed service | Legacy central stack | Legacy scrape |
| 01 | 1 | PG2 | One host-exposed service | Legacy central stack | Legacy scrape |
| 02 | 1 | PG2 | One host-exposed service | Intentionally absent | Absent |
| 03 | 1 | Redis | One host-exposed service | Intentionally absent | Absent |
| 04 | 1 | Redis | One internal site service | Intentionally absent | Absent |
| 05 | 1 | Redis | One internal site service | Intentionally absent | Absent |
| 06 | 2 | Redis | One internal service per site | Intentionally absent | Absent |
| 07 | 2 | Redis | One internal service per site | Central stack and logs | Infrastructure only |
| 08 | 2 | Redis | One internal service per site | Full telemetry paths | Site app metrics |
| 09 | 2 | Redis | One internal service per site | Full telemetry paths | BEAM and Oban safeguards |
| 10 | 2 | Redis | One internal service per site | Final verified stack | Final verified dashboards |

## State files

1. [`01-configuration-contract.md`](01-configuration-contract.md)
2. [`02-remove-legacy-observability.md`](02-remove-legacy-observability.md)
3. [`03-redis-pubsub.md`](03-redis-pubsub.md)
4. [`04-generic-site-data-analysis.md`](04-generic-site-data-analysis.md)
5. [`05-generic-app-cluster.md`](05-generic-app-cluster.md)
6. [`06-enable-second-site.md`](06-enable-second-site.md)
7. [`07-restore-central-observability.md`](07-restore-central-observability.md)
8. [`08-add-site-collectors.md`](08-add-site-collectors.md)
9. [`09-add-beam-oban-metrics.md`](09-add-beam-oban-metrics.md)
10. [`10-operational-handoff.md`](10-operational-handoff.md)

## Review after every state

Compare the implementation diff with that state's C4 delta and Terraform tree.
Reject unrelated changes, secret values in Terraform state, unlisted host ports,
stale outputs, duplicate configuration owners, and resources that depend on the
next state to become healthy.
