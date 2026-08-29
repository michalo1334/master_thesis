# State 08: Add Per-Site Telemetry Collectors

Duration: 1-2 hours.

Depends on: State 07.

## Outcome

Add one collector per site and complete trace and application-metric paths.
Collectors bridge exactly one site network and observability. They expose no
host port. Central Prometheus scrapes collector exporters instead of app
containers directly.

## Incremental C4

```mermaid
C4Container
  title State 08 - Add Per-Site Telemetry Collectors

  Boundary(west, "site-west") {
    Container(westApps, "App replicas", "Phoenix / BEAM", "Rewired to site-local telemetry")
    Container(westCollector, "Site OTel collector", "OpenTelemetry Collector", "New site and observability bridge")
  }
  Boundary(east, "site-east") {
    Container(eastApps, "App replicas", "Phoenix / BEAM", "Rewired to site-local telemetry")
    Container(eastCollector, "Site OTel collector", "OpenTelemetry Collector", "New site and observability bridge")
  }
  Boundary(central, "Central observability") {
    Container(tempo, "Tempo", "Tempo", "Now receives collector traces")
    Container(prometheus, "Prometheus", "Prometheus", "Now scrapes collector exporters")
  }

  UpdateElementStyle(westApps, $bgColor="#F9A825", $fontColor="#000000", $borderColor="#F57F17")
  UpdateElementStyle(eastApps, $bgColor="#F9A825", $fontColor="#000000", $borderColor="#F57F17")
  UpdateElementStyle(westCollector, $bgColor="#2E7D32", $fontColor="#FFFFFF", $borderColor="#1B5E20")
  UpdateElementStyle(eastCollector, $bgColor="#2E7D32", $fontColor="#FFFFFF", $borderColor="#1B5E20")
  UpdateElementStyle(tempo, $bgColor="#F9A825", $fontColor="#000000", $borderColor="#F57F17")
  UpdateElementStyle(prometheus, $bgColor="#F9A825", $fontColor="#000000", $borderColor="#F57F17")
```

The new path is: each app exports traces to its site collector; each collector
scrapes only its site's app metrics and exports traces to Tempo; central
Prometheus scrapes each collector exporter through observability.

## Terraform delta

```text
infra/environments/local/
└── ~ main.tf                                   # pass normalized sites/nodes

infra/modules/local/app/
└── ~ locals.tf                                 # site-local OTel endpoint

infra/modules/local/observability/
├── ~ main.tf                                   # collector for_each sites
├── ~ locals.tf                                 # rendered configs and aliases
├── ~ variables.tf                              # narrow site/node inputs
└── config/
    ├── + site-collector.yaml.tftpl
    ├── ~ prometheus.yaml.tftpl                 # collector targets + honor_labels
    └── - otel-collector-config.yaml             # legacy central config stays absent
```

## Changes

1. Create one collector per normalized site.
2. Attach each collector to exactly its site network and observability.
3. Give it site alias `otel-collector` and observability alias
   `otel-collector-<site>`.
4. Render explicit app-replica scrape targets from the normalized node map. Do
   not use round-robin alias `app` for metrics.
5. Add provider, region, instance, site, and replica labels to receiver static
   configs.
6. Export traces to Tempo and app metrics through the collector Prometheus
   exporter.
7. Configure central Prometheus with one collector target per site and
   `honor_labels: true`.
8. Add the site-local OTel HTTP endpoint to every app node.
9. Use `/otelcol-contrib validate` as the collector Docker healthcheck. State
   clearly that it proves config validity while PID 1 runs, not pipeline
   readiness or backend reachability.
10. Publish no collector host ports and restore none of the removed central
    collector ports.

## Review gate

Check generated aliases and target lists for every node. Check that labels come
from Prometheus receiver static configs, central Prometheus preserves them, and
no collector can attach to a second site network.

## Working-state gate

- Terraform formatting and validation pass.
- Terraform apply completes from State 07.
- Every app, analysis, collector, shared-data, and central-observability
  container is healthy.
- Collector config validation passes for both sites.
- No collector host port exists.
- Runtime acceptance remains health-only; do not claim backend delivery from
  the collector health result.

## Deferred

State 09 adds the focused BEAM and Oban safeguards and dashboard panels. The
general telemetry paths are complete at this state.
