# Firezone Observability & Monitoring Report

> Based on `/tmp/comparison_repos/firezone/elixir/` — a production Elixir/Phoenix app (Firezone Portal).

---

## 1. Telemetry — Instrumentation Layer

### 1.1 Central Telemetry Module

**File:** `lib/portal/telemetry.ex` (813 lines)

Telemetry is the backbone of all observability. The `Portal.Telemetry` module is a Supervisor that:

- Defines **5 metric groups** with handler IDs and event lists (lines 6–47)
- **Attaches/detaches** telemetry handlers at runtime via `:telemetry.attach_many/4` and `:telemetry.detach/4`
- Optionally starts a **reporter child** (configurable metrics reporter) and a **dev aggregator**
- Runs a **`telemetry_poller`** every 10 seconds for periodic BEAM measurements

```elixir
# lib/portal/telemetry.ex:6-47
@metric_groups %{
  http: %{
    handler_id: "portal-http-metrics",
    events: [
      [:phoenix, :router_dispatch, :stop],
      [:phoenix, :endpoint, :start],
      [:phoenix, :endpoint, :stop]
    ]
  },
  db: %{
    handler_id: "portal-db-metrics",
    events: [
      [:portal, :repo, :query],
      [:portal, :repo, :replica, :query],
      [:portal, :repo, :web, :query],
      [:portal, :repo, :api, :query],
      [:portal, :repo, :replica, :web, :query],
      [:portal, :repo, :replica, :api, :query]
    ]
  },
  liveview_lifecycle: %{ ... },
  liveview_events: %{ ... },
  channels: %{ ... }
}
```

**Key patterns:**

- **Runtime enable/disable** — `enable_metrics/1`, `disable_metrics/1`, `metrics_enabled?/1` (lines 751–794)
- **Config-driven startup** — telemetry only starts if `config[:enabled]` is true (line 60)
- **Plug.Telemetry integration** — endpoints use `Plug.Telemetry` with `event_prefix: [:phoenix, :endpoint]`
- **Custom events** — events like `[:portal, :repo, :query]`, `[:portal, :relays]`, `[:portal, :cluster]`

### 1.2 Telemetry.Metrics Definitions

**File:** `lib/portal/telemetry.ex:94-188`

Standard `Telemetry.Metrics` definitions (used by LiveDashboard and reporter):

| Category | Metrics | Type |
|----------|---------|------|
| Database | `portal.repo.query.total_time`, `.decode_time`, `.query_time`, `.queue_time`, `.idle_time` | `distribution`, `summary` |
| HTTP | `phoenix.router_dispatch.stop.duration` (tagged by route) | `counter`, `summary` |
| Phoenix | endpoint lifecycle, socket connected, channel join/handle_in durations | `summary` |
| VM basic | `vm.memory.total`, `vm.total_run_queue_lengths.{total,cpu,io}` | `summary` |
| BEAM health | `vm.process_count.{total,limit,utilization_percent}`, `vm.atom_count.*`, `vm.port_count.*`, `vm.ets.count`, `vm.memory.detailed.*` | `last_value` |
| GC | `vm.gc.collections_count`, `vm.gc.words_reclaimed` | `summary` |
| Scheduler | `vm.scheduler_utilization.{total,max,avg}_run_queue`, `scheduler_count` | `last_value` |
| Application | `portal.relays.online_relays_count`, `portal.cluster.discovered_nodes_count` | `last_value` |
| Directory sync | `.data_fetch_total_time`, `.db_operations_total_time`, `.total_time` (tagged by account/provider) | `summary`, `distribution` |

### 1.3 Periodic BEAM Health Measurements

**File:** `lib/portal/telemetry.ex:191-312`

Three poller callbacks emit custom telemetry every 10s:

- **`emit_beam_health_metrics/0`** — process count/utilization, atom count/utilization, port count/utilization, ETS count, detailed memory breakdown (`:erlang.memory()`)
- **`emit_gc_metrics/0`** — garbage collection collections/words_reclaimed via `:erlang.statistics(:garbage_collection)`
- **`emit_scheduler_metrics/0`** — run queue lengths, max/avg/scheduler count via `:erlang.statistics(:total_run_queue_lengths)` and `:erlang.statistics(:run_queue_lengths)`

All three are error-wrapped with `rescue` that logs and returns `:ok`.

### 1.4 Custom Telemetry Events

| Location | Event | Measurement | Purpose |
|----------|-------|-------------|---------|
| `lib/portal/cluster/postgres_strategy.ex:129` | `[:portal, :cluster]` | `%{discovered_nodes_count: n}` | Cluster discovery |
| `lib/portal/presence.ex:380` | `[:portal, :relays]` | `%{online_relays_count: n}` | Relay presence |
| `lib/portal/mailer.ex:140` | `[:swoosh, :deliver]` | span | Email delivery tracing |

### 1.5 Dev Aggregator (Development-Only)

**File:** `lib/portal/telemetry/dev_aggregator.ex` (373 lines)

A GenServer that listens to all telemetry events and prints a formatted metrics report to the console every 30 seconds. Enabled via `config :portal, Portal.Telemetry, metrics_debug: true` (disabled by default in dev, line 293 of `config/dev.exs`).

Reports: HTTP requests (by endpoint/route/method/status with min/avg/max), active requests, channel activity, LiveView activity, and DB queries.

---

## 2. Logging

### 2.1 Logger Configuration

**Base config** (`config/config.exs:509-514`):
```elixir
config :logger,
  level: System.get_env("LOG_LEVEL", "info") |> parse_log_level.()

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: :all
```

**Prod** (`config/prod.exs:62-70`) — JSON structured logging:
```elixir
config :logger,
  handle_sasl_reports: false,
  handle_otp_reports: true

config :logger_json, :config,
  metadata: {:all_except, [:socket, :conn, :otel_trace_flags]},
  redactors: [
    {LoggerJSON.Redactors.RedactKeys, secret_keys}
  ]

config :logger, level: :info
```

**Dev** (`config/dev.exs:272-275`) — custom console formatter:
```elixir
config :logger, :default_formatter,
  format: {PortalWeb.LogFormatter, :format},
  metadata: :all
```

**Test** (`config/test.exs:315`) — info level:
```elixir
config :logger, level: :info
```

### 2.2 Runtime Logger Setup

**File:** `lib/portal/application.ex:86-108`

```elixir
defp configure_logger do
  # Attach Oban to the logger
  Oban.Telemetry.attach_default_logger(encode: false, level: log_level())

  # Configure Logger severity at runtime
  :ok = LoggerJSON.configure_log_level_from_env!("LOG_LEVEL")

  config = Application.get_env(:logger_json, :config)
  if not is_nil(config) do
    formatter = LoggerJSON.Formatters.Basic.new(config)
    :logger.update_handler_config(:default, :formatter, formatter)
  end

  # Configure Sentry to capture Logger messages
  :logger.add_handler(:sentry, Sentry.LoggerHandler, %{
    config: %{level: :warning, metadata: :all, capture_log_messages: true}
  })
end
```

**Key patterns:**
- Log level set via `LOG_LEVEL` env var (defaults to `:info`), parsed at runtime
- `LoggerJSON` configured for JSON output in prod with metadata filtering and key redaction
- `Oban.Telemetry.attach_default_logger` integrates Oban job logs with the standard Logger
- `Sentry.LoggerHandler` added to capture `:warning`+ messages to Sentry

### 2.3 Dev Log Formatter

**File:** `lib/portal_web/log_formatter.ex` (72 lines)

Custom console formatter that:
- Strips Phoenix/Otel metadata (`:request_id`, `:trace_id`, `:span_id`, `:pid`, etc.)
- Colorizes log levels
- Shows only message + explicitly passed metadata as `key=value` pairs

### 2.4 Secret Redaction in Prod

**File:** `config/prod.exs:40-70`

```elixir
secret_keys = ["password", "secret", "nonce", "fragment", "state", "token",
               "public_key", "private_key", "preshared_key", "session",
               "sessions", "connection_opts"]

config :phoenix, :filter_parameters, secret_keys

config :logger_json, :config,
  redactors: [
    {LoggerJSON.Redactors.RedactKeys, secret_keys}
  ]
```

### 2.5 Metadata Propagation — request_id

Both `PortalWeb.Endpoint` and `PortalAPI.Endpoint` use `Plug.RequestId`:

```elixir
# lib/portal_web/endpoint.ex:43
plug Plug.RequestId

# lib/portal_api/endpoint.ex:28
plug Plug.RequestId
```

The request_id is:
- Passed through the `x-request-id` response header
- Captured in API request logs (`lib/portal_api/plugs/request_log.ex:38-65`)
- Stored in `portal.api_request_logs` DB table (`lib/portal/api_request_log.ex`)
- Propagated to log sinks (Splunk, Datadog, etc.) (`lib/portal/log_sinks/delivery.ex:397`)

---

## 3. Tracing / APM — OpenTelemetry

### 3.1 Dependencies

**File:** `mix.exs:120-148`

```elixir
{:opentelemetry, "~> 1.5"},
{:opentelemetry_logger_metadata, "~> 0.2.0"},
{:opentelemetry_api_experimental, github: "open-telemetry/opentelemetry-erlang", ...},
{:opentelemetry_experimental, github: "open-telemetry/opentelemetry-erlang", ...},
{:opentelemetry_exporter, "~> 1.8"},
{:opentelemetry_ecto, "~> 1.2"},
{:opentelemetry_oban, "~> 1.2.0"},
{:opentelemetry_telemetry, "~> 1.1"},
{:opentelemetry_bandit, "~> 0.3"},
{:opentelemetry_phoenix, "~> 2.0"},
{:opentelemetry_semantic_conventions, "~> 1.27"},
```

### 3.2 OpenTelemetry Setup

**File:** `lib/portal/application.ex:14-24`

```elixir
# OpenTelemetry setup
:ok = OpentelemetryLoggerMetadata.setup()
:ok = OpentelemetryEcto.setup([:portal, :repo])
:ok = OpentelemetryEcto.setup([:portal, :repo, :replica])
:ok = OpentelemetryEcto.setup([:portal, :repo, :web])
:ok = OpentelemetryEcto.setup([:portal, :repo, :api])
:ok = OpentelemetryEcto.setup([:portal, :repo, :replica, :web])
:ok = OpentelemetryEcto.setup([:portal, :repo, :replica, :api])
:ok = OpentelemetryBandit.setup()
:ok = OpentelemetryPhoenix.setup(adapter: :bandit)
:ok = OpentelemetryOban.setup()
```

This instruments:
- **Ecto** — all 8 repo instances (primary + replica, web + api + poller variants)
- **Bandit** — HTTP server spans
- **Phoenix** — router dispatch, endpoint, LiveView, channels spans
- **Oban** — job execution spans
- **Logger metadata** — attaches trace/span IDs to log metadata

### 3.3 OTel Configuration (Prod)

**File:** `config/runtime.exs:522-561`

Conditional on `OTLP_ENDPOINT` env var:

```elixir
if System.get_env("OTLP_ENDPOINT") do
  config :opentelemetry,
    resource_detectors: [:otel_resource_env_var, :otel_resource_app_env],
    resource: %{
      service: %{
        name: "portal",
        namespace: "firezone",
        version: System.get_env("RELEASE_VSN"),
        instance: %{id: System.get_env("NODE_NAME")}
      },
      host: %{
        name: System.get_env("NODE_NAME"),
        id: System.get_env("NODE_NAME")
      },
      cloud: %{provider: "azure", region: System.get_env("REGION")}
    }

  config :opentelemetry,
    span_processor: :batch,
    traces_exporter: :otlp

  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_traces_protocol: :http_protobuf,
    otlp_endpoint: System.get_env("OTLP_ENDPOINT")

  config :opentelemetry_experimental,
    readers: [%{
      module: :otel_metric_reader,
      config: %{
        export_interval_ms: 30_000,
        exporter: {:otel_exporter_metrics_otlp, %{endpoints: [System.get_env("OTLP_ENDPOINT")]}}
      }
    }]
end
```

**Key patterns:**
- Resource attributes include service name/namespace/version, host, and cloud provider (Azure)
- Batch span processor, OTLP exporter via HTTP protobuf
- OTel metrics exported every 30s via `opentelemetry_experimental` metric reader
- In dev, the same metric reader block is conditionally available (`config/dev.exs:295-306`)

### 3.4 OTel Base Config (All Envs)

**File:** `config/config.exs:505-507`

```elixir
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :none
```

In non-prod, traces exporter defaults to `:none`. `opentelemetry_experimental` SDK is disabled in tests (`config/test.exs:189`).

### 3.5 OTel Spans in Application Code

Custom manual spans using `OpenTelemetry.Tracer.with_span/3`:

```elixir
# lib/portal/cache/gateway.ex:44
OpenTelemetry.Tracer.with_span "Portal.Cache.hydrate_policy_authorizations", ...

# lib/portal/cache/client/authorizations.ex:39
OpenTelemetry.Tracer.with_span "Portal.Cache.Client.Authorizations.hydrate", ...

# lib/portal/cache/client.ex:708
OpenTelemetry.Tracer.with_span "Cache.Cacheable.hydrate", attributes: attributes do ... end
```

### 3.6 OTel Context Propagation in WebSockets

**Files:** `lib/portal_api/{client,gateway,relay}/socket.ex`

OTel context is propagated through Phoenix socket assigns:

```elixir
# lib/portal_api/client/socket.ex:227-228
|> assign(:opentelemetry_span_ctx, OpenTelemetry.Tracer.current_span_ctx())
|> assign(:opentelemetry_ctx, OpenTelemetry.Ctx.get_current())
```

And re-attached in channel modules:

```elixir
# lib/portal_api/relay/channel.ex:9-10
OpenTelemetry.Ctx.attach(socket.assigns.opentelemetry_ctx)
OpenTelemetry.Tracer.set_current_span(socket.assigns.opentelemetry_span_ctx)
```

### 3.7 OTel Metrics — Manual Instruments

**File:** `lib/portal/telemetry.ex:314-558`

`register_otel_instruments/0` creates OpenTelemetry metrics instruments using `:opentelemetry_experimental.get_meter()`:

| Instrument Type | Metric Name | Description |
|----------------|-------------|-------------|
| `observable_gauge` | `vm.process_count` | BEAM process count, limit, utilization |
| `observable_gauge` | `vm.atom_count` | BEAM atom count, limit, utilization |
| `observable_gauge` | `vm.port_count` | BEAM port count, limit, utilization |
| `observable_gauge` | `vm.ets.count` | Number of ETS tables |
| `observable_gauge` | `vm.memory` | BEAM memory (processes, system, atom, binary, code, ets) |
| `observable_gauge` | `vm.scheduler_utilization` | Run queue metrics |
| `observable_counter` | `vm.gc.collections_count` | Total garbage collections |
| `observable_counter` | `vm.gc.words_reclaimed` | Total words reclaimed |
| `counter` | `http.server.requests` | By route, method, status |
| `histogram` | `http.server.request.duration` | By route |
| `updown_counter` | `http.server.active_requests` | Currently processing |
| `histogram` | `db.query.duration` | Database query duration |
| `counter` + `histogram` | `phoenix.live_view.mounts` / `.duration` | LiveView mounts |
| `counter` + `histogram` | `phoenix.live_view.handle_params` / `.duration` | LiveView handle_params |
| `counter` + `histogram` | `phoenix.live_view.handle_events` / `.duration` | LiveView handle_event |
| `counter` + `histogram` | `phoenix.live_component.handle_events` / `.duration` | LiveComponent handle_event |
| `counter` + `histogram` | `phoenix.channel.joins` / `.duration` | Channel joins |
| `counter` + `histogram` | `phoenix.channel.messages` / `.duration` | Channel messages |

These manual instruments are populated by the telemetry event handlers (`handle_http_metric/4`, `handle_db_metric/4`, etc.) that convert telemetry events into OTel metric recordings with appropriate attributes (node_name, http.route, db.system, etc.) — see lines 565–749 of `telemetry.ex`.

---

## 4. Sentry Integration (Error Tracking)

### 4.1 Sentry Configuration

**Base** (`config/config.exs:560-567`):
```elixir
config :sentry,
  before_send: {Portal.Telemetry.Sentry, :before_send},
  dsn: nil,
  environment_name: :unknown,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]
```

**Prod** (`config/runtime.exs:600-613`) — configured conditionally:
```elixir
with api_external_url when not is_nil(api_external_url) <-
       env_var_to_config!(:api_external_url),
     api_external_url_host <- URI.parse(api_external_url).host,
     environment_name when environment_name in [:staging, :production] <-
       (cond do
          String.contains?(api_external_url_host, "firezone.dev") -> :production
          String.contains?(api_external_url_host, "firez.one") -> :staging
          true -> :unknown
        end) do
  config :sentry,
    environment_name: environment_name,
    dsn: env_var_to_config!(:sentry_dsn)
end
```

Environment detection is automatic based on the API external URL hostname.

### 4.2 Before Send Callback — Event Filtering

**File:** `lib/portal/telemetry/sentry.ex` (39 lines)

Filters out noise before sending to Sentry:

- Exceptions with `%{skip_sentry: true}` metadata
- `Ecto.NoResultsError` — expected under normal operation
- `Plug.CSRFProtection.InvalidCSRFTokenError` — bots/malicious actors
- Libcluster connection/disconnection messages (4 regex patterns)

### 4.3 Sentry Logger Handler

**File:** `lib/portal/application.ex:100-107`

```elixir
:logger.add_handler(:sentry, Sentry.LoggerHandler, %{
  config: %{level: :warning, metadata: :all, capture_log_messages: true}
})
```

Captures all Logger messages at `:warning`+ level to Sentry. Cleaned up on shutdown (line 33):
```elixir
_ = :logger.remove_handler(:sentry)
```

### 4.4 Sentry Plug Context

Both web and API endpoints add `Sentry.PlugContext` to attach request context to errors:

```elixir
# lib/portal_web/endpoint.ex:77
plug Sentry.PlugContext

# lib/portal_api/endpoint.ex:88
plug Sentry.PlugContext
```

---

## 5. Oban Telemetry & Error Reporter

### 5.1 Oban Default Logger

**File:** `lib/portal/application.ex:88`

```elixir
Oban.Telemetry.attach_default_logger(encode: false, level: log_level())
```

Logs Oban job lifecycle events via standard Logger at configured level.

### 5.2 Oban Sentry Reporter

**File:** `lib/portal/telemetry/reporter/oban.ex` (57 lines)

Attaches to `[:oban, :job, :exception]` and forwards exceptions to Sentry:

```elixir
def attach do
  :telemetry.attach("oban-errors", [:oban, :job, :exception], &__MODULE__.handle_event/4, [])
end

def handle_event([:oban, :job, :exception], _measure, meta, _config) do
  sentry_context = safe_handle_error(meta)
  Sentry.capture_exception(meta.reason, stacktrace: meta.stacktrace, extra: sentry_context)
end
```

Domain-specific error handlers for directory sync workers (`Portal.Entra.Sync`, `Portal.Google.Sync`, `Portal.Okta.Sync`) add contextual Sentry data (lines 45-46).

### 5.3 Oban OpenTelemetry

**File:** `lib/portal/application.ex:24`

```elixir
:ok = OpentelemetryOban.setup()
```

Instruments Oban job execution with OpenTelemetry spans.

---

## 6. Health Checks

### 6.1 Health Check Plug

**File:** `lib/portal/health.ex` (95 lines)

A Plug that intercepts `GET /readyz` and returns JSON with status:

```elixir
def call(%Plug.Conn{request_path: "/readyz", method: "GET"} = conn, _opts) do
  conn
  |> put_resp_content_type("application/json")
  |> send_readyz_response()
  |> halt()
end
```

**Status responses:**

| Condition | HTTP Status | JSON Body |
|-----------|-------------|-----------|
| Draining file exists | `503` | `{"status":"draining","version":"..."}` |
| Endpoint not registered | `503` | `{"status":"starting","version":"..."}` |
| DB query fails (`SELECT 1`) | `503` | `{"status":"database_unavailable","version":"..."}` |
| All healthy | `200` | `{"status":"ready","version":"..."}` |

**Readiness checks:**
- **Draining** — checks for a sentinel file at `draining_file_path` (e.g., `/var/run/firezone/draining`)
- **Endpoints** — verifies `Process.whereis/1` for PortalWeb, PortalAPI, PortalOps endpoints
- **Database** — runs `SELECT 1` on 6 repos (excludes poller pools deliberately)

**Configuration** (`config/config.exs:216-222`):
```elixir
config :portal, Portal.Health,
  web_endpoint: PortalWeb.Endpoint,
  api_endpoint: PortalAPI.Endpoint,
  ops_endpoint: PortalOps.Endpoint,
  draining_file_path: "/var/run/firezone/draining"
```

### 6.2 Where Health Plug is Wired

- `PortalWeb.Endpoint` — line 21 (early in pipeline)
- `PortalAPI.Endpoint` — line 5 (early in pipeline)
- `PortalOps.Endpoint` — does NOT include the health plug (it's admin-only)

---

## 7. Prometheus / LiveDashboard

### 7.1 Phoenix LiveDashboard

**File:** `lib/portal_ops/router.ex:36-40`

```elixir
live_dashboard "/dashboard",
  metrics: Portal.Telemetry,
  live_socket_path: "/dashboard/live"
```

Served on the Ops endpoint with HTTP basic auth. Uses `Portal.Telemetry.metrics/0` for metric definitions.

### 7.2 Oban Web Dashboard

**File:** `lib/portal_ops/router.ex:35`

```elixir
oban_dashboard "/oban"
```

Also on the Ops endpoint.

### 7.3 No Prometheus Exporter

No Prometheus exporter library (`prometheus.ex`, `prometheus_ecto`, `prometheus_phoenix`) is used. Metrics are exported via OpenTelemetry OTLP instead (see §3.3).

### 7.4 Other Tools

| Tool | Purpose | Config |
|------|---------|--------|
| `recon` | BEAM introspection (production-safe) | `mix.exs:124` |
| `observer_cli` | Terminal-based observer | `mix.exs:125` |
| `ecto_psql_extras` | PostgreSQL diagnostics | `mix.exs:73` |

---

## 8. Summary Table

| Concern | Technology | Key Files |
|---------|-----------|-----------|
| **Telemetry events** | `:telemetry` (Erlang), custom event prefixes | `lib/portal/telemetry.ex` |
| **Telemetry.Metrics** | `Telemetry.Metrics` | `lib/portal/telemetry.ex:94-188` |
| **Periodic measurements** | `telemetry_poller` (10s) | `lib/portal/telemetry.ex:191-312` |
| **Tracing** | OpenTelemetry (batch processor, OTLP exporter) | `config/runtime.exs:522-561` |
| **OTel instrumentation** | Ecto, Bandit, Phoenix, Oban, Logger metadata | `lib/portal/application.ex:14-24` |
| **OTel manual metrics** | `opentelemetry_experimental` (observable gauges, counters, histograms) | `lib/portal/telemetry.ex:314-558` |
| **OTel custom spans** | `OpenTelemetry.Tracer.with_span/3` | Cache modules, channel sockets |
| **Error tracking** | Sentry (DSN, before_send filter, LoggerHandler, PlugContext) | `config/config.exs:560-567`, `lib/portal/telemetry/sentry.ex` |
| **Oban errors → Sentry** | Custom telemetry reporter | `lib/portal/telemetry/reporter/oban.ex` |
| **Structured logging** | `logger_json` (prod), custom formatter (dev) | `config/prod.exs:62-70`, `lib/portal_web/log_formatter.ex` |
| **Log level** | `LOG_LEVEL` env var, runtime-configured | `lib/portal/application.ex:86-117` |
| **Metadata redaction** | `LoggerJSON.Redactors.RedactKeys` | `config/prod.exs:66-70` |
| **Health checks** | Custom `Portal.Health` plug at `/readyz` | `lib/portal/health.ex` |
| **LiveDashboard** | `Phoenix.LiveDashboard` on Ops endpoint | `lib/portal_ops/router.ex:37-39` |
| **Oban Web** | `Oban.Web` on Ops endpoint | `lib/portal_ops/router.ex:35` |
| **request_id** | `Plug.RequestId` on all endpoints | `lib/portal_web/endpoint.ex:43`, `lib/portal_api/endpoint.ex:28` |
