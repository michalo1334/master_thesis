# State 07: Restore Central Observability

Duration: 1-2 hours.

Depends on: State 06.

## Outcome

Reintroduce the central observability and management services on the dedicated
observability network. Restore infrastructure metrics and the JSONL log path.
Do not add site collectors or app traces/metrics yet. Tempo and the app-metric
portion of Prometheus can be healthy but idle until State 08.

## Incremental C4

```mermaid
C4Container
  title State 07 - Restore Central Observability

  Boundary(core, "Existing two-site core") {
    Container(apps, "Two BEAM sites", "Phoenix / BEAM", "Writes site-qualified JSONL logs")
    ContainerDb(postgres, "PostgreSQL", "PostgreSQL", "Existing shared database")
    ContainerQueue(redis, "Redis", "Redis", "Existing cross-site PubSub")
  }
  Boundary(observability, "Central observability network") {
    Container(grafana, "Grafana", "Grafana", "Dashboards and all-site entry point")
    Container(prometheus, "Prometheus", "Prometheus", "Infrastructure metrics; app metrics deferred")
    Container(tempo, "Tempo", "Tempo", "Healthy trace store; app traces deferred")
    Container(loki, "Loki", "Loki", "Central log store")
    Container(alloy, "Alloy", "Alloy", "Reads shared JSONL logs")
    Container(exporters, "Exporters", "cAdvisor, node, PostgreSQL", "Container, host, and DB metrics")
  }

  UpdateElementStyle(apps, $bgColor="#F9A825", $fontColor="#000000", $borderColor="#F57F17")
  UpdateElementStyle(postgres, $bgColor="#546E7A", $fontColor="#FFFFFF", $borderColor="#37474F")
  UpdateElementStyle(redis, $bgColor="#546E7A", $fontColor="#FFFFFF", $borderColor="#37474F")
  UpdateElementStyle(grafana, $bgColor="#2E7D32", $fontColor="#FFFFFF", $borderColor="#1B5E20")
  UpdateElementStyle(prometheus, $bgColor="#2E7D32", $fontColor="#FFFFFF", $borderColor="#1B5E20")
  UpdateElementStyle(tempo, $bgColor="#2E7D32", $fontColor="#FFFFFF", $borderColor="#1B5E20")
  UpdateElementStyle(loki, $bgColor="#2E7D32", $fontColor="#FFFFFF", $borderColor="#1B5E20")
  UpdateElementStyle(alloy, $bgColor="#2E7D32", $fontColor="#FFFFFF", $borderColor="#1B5E20")
  UpdateElementStyle(exporters, $bgColor="#2E7D32", $fontColor="#FFFFFF", $borderColor="#1B5E20")
```

## Terraform delta

```text
infra/environments/local/
├── ~ main.tf                              # restore observability module call
└── ~ outputs.tf                           # restore Grafana and Prometheus URLs

infra/modules/local/observability/
├── + main.tf                              # central services only
├── + variables.tf
├── + locals.tf
├── + versions.tf
└── + config/
    ├── + alloy-config.alloy               # site-qualified JSONL regex
    ├── + prometheus.yaml.tftpl            # infra jobs; no site collectors yet
    ├── + tempo.yaml
    ├── + loki-config.yaml
    ├── + postgres-exporter.yaml
    ├── + postgres-exporter-init.sh
    └── + grafana-provisioning/
```

## Changes

1. Recreate Grafana, Prometheus, Tempo, Loki, Alloy, cAdvisor, node-exporter,
   postgres-exporter, and its init container on observability.
2. Keep pgAdmin in the database module. Do not duplicate it.
3. Publish only Grafana and Prometheus loopback ports from this module.
4. Keep Loki, Tempo, Alloy, and exporters internal.
5. Mount the root application log volume into Alloy read-only. Parse
   `app.<site>.<replica>.jsonl` into site and replica labels and push to Loki.
6. Provision Grafana datasources for available central services.
7. Configure Prometheus for itself and infrastructure exporters only. Do not add
   app or collector targets before collectors exist.
8. Keep Tempo healthy with no app trace producer.
9. Read exporter secrets from mounted files at runtime; do not place values in
   Terraform state.

## Destructive effects

This state creates new observability volumes after the State 02 teardown.
Historical telemetry remains lost. The new host-port policy intentionally does
not restore direct Loki, Tempo, Alloy, or collector ports.

## Review gate

Check network membership, host ports, volume ownership, secret paths, and
Prometheus targets. Reject any app OTel endpoint or site-collector target in
this state.

## Working-state gate

- Terraform formatting and validation pass.
- Terraform apply completes from State 06.
- All two-site core containers remain healthy.
- Grafana, Prometheus, Tempo, Loki, Alloy, cAdvisor, node-exporter,
  postgres-exporter, and its init step are healthy or exit zero as designed.
- Available outputs list app, PostgreSQL, Grafana, pgAdmin, and Prometheus only.

## Deferred

State 08 adds per-site collectors, app trace export, and site app metrics.
