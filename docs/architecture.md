# Overview

System architecture described with the C4 model (Mermaid). Levels: System Context, two Container diagrams (application and observability), and Deployment. Two Mermaid sequence diagrams cover the flows a static topology cannot show — an attack-simulation run and the observability pipeline.

Element aliases stay consistent across diagrams so the same node resolves from one level to the next. Ports, image tags, and versions live in Terraform and Docker configuration; the prose points to them instead of restating values.

Flows use `sequenceDiagram` rather than `C4Dynamic`: the simulation run loops back through the same boxes, and the observability pipeline runs concurrently, both of which `C4Dynamic` renders with overlapping labels in Mermaid. Sequence diagrams handle returns and parallel notes without stacking.

## Level 1 — System Context

The analyst drives everything; NVD is the only external system the application depends on.

```mermaid
C4Context
  title System Context — Network Defense

  Person(securityAnalyst, "Security Analyst / Researcher", "Models topology, runs simulations, evaluates defenses")
  System(networkDefense, "Network Defense", "Graph-based attack-propagation simulation and defense optimization")
  System_Ext(nvdApi, "NVD API", "Source of real CVE and vulnerability data")

  Rel(securityAnalyst, networkDefense, "Models topology, runs simulations, applies defenses via", "HTTPS")
  Rel(networkDefense, nvdApi, "Fetches vulnerability data", "HTTPS")
```

NVD integration is declared in the technology stack (see `README.md`); no fetcher client exists in `src/lib` yet, so this is the intended external dependency for real CVE data.

## Level 2 — Container, Application

The application boundary only. A single OTP application (`src/lib/network_defense/application.ex`) hosts the Phoenix web layer, the domain engine (graph, simulation, optimization), and Ecto persistence; Svelte 5 renders through LiveSvelte.

```mermaid
C4Container
  title Container — Application

  UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")

  Person(securityAnalyst, "Security Analyst", "Drives simulations and defenses from the browser")
  System_Ext(nvdApi, "NVD API", "Vulnerability data")

  System_Boundary(networkDefense, "Network Defense") {
    Container(spa, "Dashboard SPA", "Svelte 5, LiveSvelte, Bits UI, Tailwind", "Topology editor, controls, simulation report")
    Container(phoenix, "Phoenix App", "Elixir, Phoenix LiveView, Bandit", "Web layer, domain engine, persistence")
    ContainerDb(postgres, "PostgreSQL", "PostgreSQL 18", "Graphs, nodes, edges, simulations, iteration steps")
  }

  Rel(securityAnalyst, spa, "Uses", "HTTPS")
  Rel(spa, phoenix, "LiveView events both ways", "WebSocket")
  Rel(phoenix, postgres, "Reads/writes", "Ecto")
  Rel(phoenix, nvdApi, "Fetches vulnerability data", "HTTPS")
```

## Level 2 — Container, Observability Stack

The observability wiring in isolation. Traces and metrics leave the app by OTLP through the collector; logs bypass the collector and reach Loki via Alloy tailing the shared JSONL file, which keeps compile noise and framework banners out of Loki (see `infra/modules/local/observability/config/alloy-config.alloy` and `docs/infrastructure.md`). Grafana correlates traces with logs through `trace_id` structured metadata. `node-exporter`, `cadvisor`, and `postgres-exporter` are also scraped by Prometheus but omitted here as generic or peripheral infrastructure. The app's log-write path is shown in the Deployment and Observability Pipeline diagrams; here `jsonlLogs` is the file Alloy tails.

```mermaid
C4Container
  title Container — Observability Stack

  UpdateLayoutConfig($c4ShapeInRow="4", $c4BoundaryInRow="1")

  Container_Ext(phoenix, "Phoenix App", "Elixir", "Source of OTLP and the JSONL log file")
  Container(otelCollector, "OTel Collector", "otel-collector-contrib", "Receives OTLP, fans out traces and metrics")
  Container(tempo, "Tempo", "Grafana Tempo", "Trace store")
  Container(prometheus, "Prometheus", "Prometheus", "Metrics TSDB")
  Container(grafana, "Grafana", "Grafana", "Dashboards with trace-log correlation")
  Container(loki, "Loki", "Grafana Loki", "Log store")
  Container(alloy, "Alloy", "Grafana Alloy", "Tails the app JSONL log file")
  ContainerDb(jsonlLogs, "App JSONL Logs", "File on network-defense-log volume", "Structured Logger output")

  Rel(phoenix, otelCollector, "Exports traces and metrics", "OTLP/HTTP")
  Rel(otelCollector, tempo, "Forwards spans", "OTLP/gRPC")
  Rel(prometheus, otelCollector, "Scrapes metrics exporter", "HTTP")
  Rel(alloy, jsonlLogs, "Tails", "read-only mount")
  Rel(alloy, loki, "Pushes parsed logs", "HTTP")
  Rel(grafana, prometheus, "Queries metrics", "HTTP")
  Rel(grafana, tempo, "Queries traces", "HTTP, correlates with Loki via trace_id")
  Rel(grafana, loki, "Queries logs", "HTTP")

  UpdateRelStyle(phoenix, otelCollector, $offsetY="-15")
  UpdateRelStyle(grafana, prometheus, $offsetY="-15")
```

## Deployment

A Terraform-managed Docker deployment. Dev publishes everything to loopback, migrates and seeds before app startup, and backs secrets with files. Internal observability wiring, the shared log volume, and exporter scrape targets are shown in the Container — Observability diagram; here the stack is drawn only for placement with the app-to-stack feed.

```mermaid
C4Deployment
  title Deployment — Terraform-Managed Docker

  UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")

  Person(securityAnalyst, "Security Analyst", "Uses the dashboard")

  Deployment_Node(browser, "Analyst Browser", "Chrome/Firefox") {
    Container(spa, "Dashboard SPA", "Svelte 5", "Topology editor and reports")
  }

  Deployment_Node(host, "Docker Host", "Linux") {
    Deployment_Node(app, "App", "Elixir release") {
      Container(phoenix, "Phoenix App", "Elixir, Bandit", "Web :4000, metrics :4001")
      Container(migration, "Migration Job", "Elixir release", "One-shot /app/bin/migrate, prod")
    }
    Deployment_Node(data, "Data", "PostgreSQL 18") {
      ContainerDb(postgres, "PostgreSQL", "PostgreSQL", "Persistence")
    }
    Deployment_Node(obs, "Observability Stack", "Grafana stack") {
      Container(otelCollector, "OTel Collector", "otel-collector-contrib", "OTLP receiver")
      Container(tempo, "Tempo", "Grafana Tempo", "Traces")
      Container(prometheus, "Prometheus", "Prometheus", "Metrics")
      Container(loki, "Loki", "Grafana Loki", "Logs")
      Container(alloy, "Alloy", "Grafana Alloy", "File tailer")
      Container(grafana, "Grafana", "Grafana", "Dashboards")
    }
  }

  Rel(securityAnalyst, spa, "Uses", "HTTPS")
  Rel(spa, phoenix, "LiveView events", "WebSocket")
  Rel(phoenix, postgres, "Reads/writes", "Ecto")
  Rel(phoenix, otelCollector, "Exports OTLP and writes logs", "HTTP / file")
  Rel(migration, postgres, "Applies migrations", "Ecto")
```

## Flow — Attack-Simulation Run

The user triggers a run from the SPA; the LiveView accepts it, hands work to a supervised task that runs Monte Carlo iterations with propagated OTel context, persists results, and pushes a contract-validated completion event back over PubSub. See `dashboard_live.ex` and `Simulations.run_async/1`.

```mermaid
sequenceDiagram
  title Attack-Simulation Run

  participant SPA as Dashboard SPA
  participant LV as DashboardLive (Elixir)
  participant Sim as Simulations
  participant TS as TaskSupervisor
  participant Eng as Simulator
  participant DB as PostgreSQL

  SPA->>LV: run_simulation_request (WebSocket)
  LV->>Sim: Simulations.run_async
  Sim->>TS: start_child (OTel span propagated)
  TS->>Eng: execute Monte Carlo runs (seeded)
  Eng->>DB: persist experiment & steps (Ecto)
  Sim-->>LV: broadcast simulation_completed (PubSub)
  LV-->>SPA: push_event simulation_completed (WebSocket)
```

## Flow — Observability Pipeline

Two pipelines run concurrently: traces and metrics go OTLP through the collector; logs reach Loki via Alloy tailing the shared JSONL file. Grafana correlates traces with logs through `trace_id` structured metadata. Pull-based operations (Prometheus scraping, Alloy tailing) are continuous, noted below.

```mermaid
sequenceDiagram
  title Observability Pipeline

  participant App as Phoenix App
  participant Coll as OTel Collector
  participant Tempo as Tempo
  participant Prom as Prometheus
  participant Logs as App JSONL Logs
  participant Alloy as Alloy
  participant Loki as Loki
  participant Graf as Grafana

  Note over App,Logs: two pipelines run concurrently
  App->>Coll: export traces & metrics (OTLP/HTTP)
  Coll->>Tempo: forward spans (OTLP/gRPC)
  Note over Prom,Coll: continuous pull
  Prom->>Coll: scrape metrics exporter (HTTP)
  App->>Logs: write structured logs (file)
  Note over Alloy,Logs: continuous tail
  Alloy->>Logs: tail (read-only mount)
  Alloy->>Loki: push parsed logs (HTTP)
  Graf->>Prom: query metrics (HTTP)
  Graf->>Tempo: query traces, correlate with Loki via trace_id (HTTP)
  Graf->>Loki: query logs (HTTP)
```
