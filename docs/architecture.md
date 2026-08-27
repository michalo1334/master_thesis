# Architecture

This page describes the current system architecture with the C4 model. It uses
Mermaid diagrams. Element aliases stay consistent across diagrams so the same
node resolves from one level to the next.

Container ports, image tags, and versions live in Terraform and Docker
configuration. The prose points to those files instead of restating values
(see [infrastructure.md](infrastructure.md) and the modules listed there).

## Level 1: System Context

```mermaid
C4Context
  title System Context: Network Defense

  Person(securityAnalyst, "Security Analyst", "Models topology, runs simulations, evaluates defenses")
  System(networkDefense, "Network Defense", "Graph-based attack-propagation simulation and defense evaluation")

  Rel(securityAnalyst, networkDefense, "Models topology, runs simulations, evaluates defenses", "HTTPS")
```

NVD ingestion is deferred and no runtime fetch occurs (see
[scope.md](concepts/scope.md)). The built-in catalog contains synthetic entries.
The baseline scenario can also use a reviewed static NVD subset. Both sources
are local data. The system has no runtime network dependency on an external
vulnerability source.

## Level 2: Container, Application

The application is a single OTP application
([`src/lib/network_defense/application.ex`](../src/lib/network_defense/application.ex)).
It hosts the Phoenix web layer, the domain engine (graph, simulation,
defense, evaluation), and Ecto persistence. Svelte 5 renders through
LiveSvelte. The browser talks to the LiveView over a WebSocket.

```mermaid
C4Container
  title Container: Application

  UpdateLayoutConfig($c4ShapeInRow="2", $c4BoundaryInRow="1")

  Person(securityAnalyst, "Security Analyst", "Drives simulations and evaluations from the browser")

  System_Boundary(networkDefense, "Network Defense") {
    Container(spa, "Dashboard SPA", "Svelte 5, LiveSvelte, TypeScript", "Topology editor, controls, report view")
    Container(phoenix, "Phoenix App", "Elixir, Phoenix LiveView, Bandit", "Web layer, domain engine, Ecto persistence")
    ContainerDb(postgres, "PostgreSQL", "PostgreSQL", "Graphs, revisions, simulations, evaluation runs")
  }

  Rel(securityAnalyst, spa, "Uses", "HTTPS")
  Rel(spa, phoenix, "LiveView events", "WebSocket")
  Rel(phoenix, postgres, "Reads and writes", "Ecto")
```

### Backend-to-frontend contract generation

The frontend gets its data model from the backend. Backend contract types are
the single source; `mix gen.contracts`
([`src/lib/mix/tasks/gen.contracts.ex`](../src/lib/mix/tasks/gen.contracts.ex))
parses their typespecs and writes generated TypeScript to
`src/assets/svelte/contracts.generated.ts`. Svelte components import those
generated types. This keeps the frontend types in sync with the backend.

## Level 2: Container, Analysis Service and Observability Stack

Statistical analysis runs in a separate local Python service. The app hands a
completed evaluation result archive to it over HTTP and receives a result
archive back. Analysis follows a completed evaluation or export; it is a
follow-on step, not part of the run itself. The detailed methods are described
in the [analysis README](../evaluation/analysis/README.md), not here.

The observability services store telemetry. Traces and metrics leave the app
by OTLP through the collector. Logs bypass the collector: Alloy tails the
shared structured-log volume and pushes parsed logs to Loki, which keeps
compile noise out of Loki (see the Alloy configuration in
`infra/modules/local/observability/config`). Grafana correlates traces with
logs.

```mermaid
C4Container
  title Container: Analysis Service and Observability Stack

  UpdateLayoutConfig($c4ShapeInRow="4", $c4BoundaryInRow="1")

  Container_Ext(phoenix, "Phoenix App", "Elixir", "Source of OTLP and the structured log file")
  Container_Ext(analysisSvc, "Analysis Service", "Python, Starlette", "Statistical analysis of result archives")

  Container(otelCollector, "OTel Collector", "otel-collector-contrib", "Receives OTLP, fans out traces and metrics")
  Container(tempo, "Tempo", "Grafana Tempo", "Trace store")
  Container(prometheus, "Prometheus", "Prometheus", "Metrics TSDB")
  Container(grafana, "Grafana", "Grafana", "Dashboards with trace-log correlation")
  Container(loki, "Loki", "Grafana Loki", "Log store")
  Container(alloy, "Alloy", "Grafana Alloy", "Tails the structured-log volume")
  ContainerDb(jsonlLogs, "Structured Log Volume", "Shared file volume", "Structured Logger output, one file per app replica")

  Rel(phoenix, analysisSvc, "Posts result archive, receives result", "HTTP")
  Rel(phoenix, otelCollector, "Exports traces and metrics", "OTLP/HTTP")
  Rel(otelCollector, tempo, "Forwards spans", "OTLP/gRPC")
  Rel(prometheus, otelCollector, "Scrapes metrics exporter", "HTTP")
  Rel(alloy, jsonlLogs, "Tails", "read-only mount")
  Rel(alloy, loki, "Pushes parsed logs", "HTTP")
  Rel(grafana, prometheus, "Queries metrics", "HTTP")
  Rel(grafana, tempo, "Queries traces, correlates with Loki via trace_id", "HTTP")
  Rel(grafana, loki, "Queries logs", "HTTP")

  UpdateRelStyle(phoenix, otelCollector, $offsetY="-15")
  UpdateRelStyle(grafana, prometheus, $offsetY="-15")
```

## Deployment

The system runs as a Terraform-managed Docker stack. The stack shows a
production-like placement: a replicated app service, the database, the Python
analysis service, the observability services, and the shared structured-log
volume.

The setup applies in development. In production, a one-shot migration job runs
`/app/bin/migrate` before the app starts instead of the development setup step.

```mermaid
C4Deployment
  title Deployment: Terraform-Managed Docker Stack

  UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")

  Person(securityAnalyst, "Security Analyst", "Uses the dashboard")

  Deployment_Node(browser, "Analyst Browser", "Chrome or Firefox") {
    Container(spa, "Dashboard SPA", "Svelte 5", "Topology editor and reports")
  }

  Deployment_Node(host, "Docker Host", "Linux") {
    Deployment_Node(app, "App", "Elixir release") {
      Container(phoenix, "Phoenix App", "Elixir, Bandit", "Replicated service")
    }
    Deployment_Node(analysis, "Analysis", "Python") {
      Container(analysisSvc, "Analysis Service", "Python, Starlette", "Statistical analysis")
    }
    Deployment_Node(data, "Data", "PostgreSQL") {
      ContainerDb(postgres, "PostgreSQL", "PostgreSQL", "Persistence")
    }
    Deployment_Node(logs, "Shared Volume", "Structured logs") {
      ContainerDb(jsonlLogs, "Structured Log Volume", "File volume", "One log file per app replica")
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
  Rel(phoenix, postgres, "Reads and writes", "Ecto")
  Rel(phoenix, analysisSvc, "Posts result archive, receives result", "HTTP")
  Rel(phoenix, jsonlLogs, "Writes structured logs", "file")
  Rel(alloy, jsonlLogs, "Tails", "read-only mount")
  Rel(phoenix, otelCollector, "Exports OTLP", "HTTP")
```

The app service scales by configured replicas; each replica writes its own
structured log file to the shared application-log volume, and Alloy tails that
directory. The replication count and other sizes are Terraform inputs in
`infra/environments/local`.

## Engineering rationale

The reasons below cover only non-obvious boundaries.

- **One application.** A single OTP app hosts the web layer, the domain
  engine, and Ecto persistence. The domain shares LiveView context and read
  models with no separate service boundary.
- **Separate analysis service.** Statistical analysis is heavy numeric work
  with its own toolchain. A separate Python service keeps that toolchain out
  of the Elixir release and isolates its failure mode from the app.
- **Logs by file tail.** Logs bypass the collector and reach Loki through Alloy
  tailing the shared volume. This keeps framework banners and compile noise
  out of Loki and keeps the app log-write path simple.
