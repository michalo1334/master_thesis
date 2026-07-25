# Plausible Observability & Monitoring

> Analyzed from `/tmp/comparison_repos/plausible` (self-hosted analytics platform, Elixir/Phoenix).

---

## Table of Contents

1. [Structured Logging](#1-structured-logging)
2. [Logger Configuration](#2-logger-configuration)
3. [Sentry (Error Tracking / APM)](#3-sentry-error-tracking--apm)
4. [OpenTelemetry (Distributed Tracing)](#4-opentelemetry-distributed-tracing)
5. [BEAM Process Metrics (OTel)](#5-beam-process-metrics-otel)
6. [PromEx / Prometheus (Application Metrics)](#6-promex--prometheus-application-metrics)
7. [Telemetry Events (Custom Instrumentation)](#7-telemetry-events-custom-instrumentation)
8. [Health Checks](#8-health-checks)
9. [Dependency Summary](#9-dependency-summary)

---

## 1. Structured Logging

### JSON log format via `ex_json_logger`

Plausible supports two log formats controlled by `LOG_FORMAT` env var:

- `"standard"` — default human-readable format
- `"json"` — structured JSON logging via `ExJsonLogger`

**`config/runtime.exs` lines 23–46:**

```elixir
log_format =
  get_var_from_path_or_env(config_dir, "LOG_FORMAT", "standard")

case String.downcase(log_format) do
  "standard" ->
    config :logger, :default_formatter, format: "$time $metadata[$level] $message\n"

  "json" ->
    config :logger, :default_formatter, format: {ExJsonLogger, :format}
end
```

### Log level

Controlled by `LOG_LEVEL` env var. Default differs by environment:

- `:ce` → `:notice`
- All others → `:warning`

**`config/runtime.exs` lines 26–33:**

```elixir
default_log_level = if config_env() == :ce, do: "notice", else: "warning"

log_level =
  config_dir
  |> get_var_from_path_or_env("LOG_LEVEL", default_log_level)
  |> String.to_existing_atom()

config :logger, level: log_level
```

### Metadata propagation

`request_id` and `trace_id` are always included in log metadata:

**`config/runtime.exs` line 34:**

```elixir
config :logger, :default_formatter, metadata: [:request_id, :trace_id]
```

The `trace_id` is injected into Logger metadata via an OTel telemetry handler (see [Section 4](#4-opentelemetry-distributed-tracing)).

### Custom request logging (duration + query params)

A custom `:telemetry` handler replaces Phoenix's default request logging to include duration and query parameters on a single line:

**`lib/plausible/request_logger.ex` (19 lines):**

```elixir
defmodule Plausible.RequestLogger do
  require Logger

  def log_request(_, %{duration: duration}, %{conn: conn}, _) do
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)
    path = path_with_params(conn.request_path, conn.query_string)

    Logger.info("(#{conn.status}) #{conn.method} #{path} took #{duration_ms}ms")
  end

  defp path_with_params(request_path, ""), do: request_path
  defp path_with_params(request_path, query_string), do: request_path <> "?" <> query_string
end
```

Attached in `Plausible.Application.start/2`:

**`lib/plausible/application.ex` lines 351–358:**

```elixir
def setup_request_logging() do
  :telemetry.attach(
    "plausible-request-logging",
    [:phoenix, :endpoint, :stop],
    &Plausible.RequestLogger.log_request/4,
    %{}
  )
end
```

---

## 2. Logger Configuration

### Sentry LoggerBackend

Sentry captures log messages at `:error` level and above:

**`config/runtime.exs` lines 36–38:**

```elixir
config :logger, Sentry.LoggerBackend,
  capture_log_messages: true,
  level: :error
```

### Failed login attempt logging

Optional, controlled by `LOG_FAILED_LOGIN_ATTEMPTS` env var:

**`config/runtime.exs` line 324–325:**

```elixir
log_failed_login_attempts =
  get_bool_from_path_or_env(config_dir, "LOG_FAILED_LOGIN_ATTEMPTS", false)
```

---

## 3. Sentry (Error Tracking / APM)

### Dependencies

**`mix.exs` line 148:**

```elixir
{:sentry, "~> 11.0.4"},
```

Also uses the companion `logger_backends` package:

**`mix.exs` line 183:**

```elixir
{:logger_backends, "~> 1.0.0"}
```

### Configuration

**`config/runtime.exs` lines 596–606:**

```elixir
config :sentry,
  dsn: sentry_dsn,
  environment_name: env,
  release: sentry_app_version,
  tags: %{
    app_version: sentry_app_version,
    app_host: app_host
  },
  client: Plausible.Sentry.Client,
  send_max_attempts: 1,
  before_send: {Plausible.SentryFilter, :before_send}
```

**`config/config.exs` lines 77–79:**

```elixir
config :sentry,
  enable_source_code_context: true,
  root_source_code_path: [File.cwd!()]
```

Key points:

- `send_max_attempts: 1` — no retries (fail fast)
- Custom `Sentry.HTTPClient` implementation using Finch (see below)
- Custom `before_send` filter (see [SentryFilter](#sentryfilter))
- Source code context is enabled in config.exs

### Custom HTTP Client via Finch

Plausible implements `Sentry.HTTPClient` behaviour to use its own Finch pool instead of the default hackney:

**`lib/plausible/sentry/client.ex` (32 lines):**

```elixir
defmodule Plausible.Sentry.Client do
  @behaviour Sentry.HTTPClient

  def post(url, headers, body) do
    req_opts = Application.get_env(:plausible, __MODULE__)[:finch_request_opts] || []

    :post
    |> Finch.build(url, headers, body)
    |> Finch.request(Plausible.Finch, req_opts)
    |> handle_response()
  end
end
```

Custom Finch pool size for Sentry (50 connections) configured in application.ex:

**`lib/plausible/application.ex` lines 278–285:**

```elixir
defp maybe_add_sentry_pool(pool_config, default) do
  case Sentry.Config.dsn() do
    %{endpoint_uri: "http" <> _rest = url} ->
      Map.put(pool_config, url, Config.Reader.merge(default, size: 50))
    nil -> pool_config
  end
end
```

### SentryFilter

Filters and groups Sentry events by type. Drops noise, groups transport errors:

**`lib/sentry_filter.ex` (69 lines):**

```elixir
defmodule Plausible.SentryFilter do
  # Drops hard bounces from Postmark
  def before_send(%{original_exception: %Bamboo.PostmarkAdapter.Error{} = e} = event) do
    if Bamboo.PostmarkAdapter.Error.is_hard_bounce(e), do: false, else: event
  end

  # Drops these entirely
  def before_send(%{original_exception: %Phoenix.NotAcceptableError{}}), do: false
  def before_send(%{original_exception: %Plug.CSRFProtection.InvalidCSRFTokenError{}}), do: false
  def before_send(%{original_exception: %Plug.Static.InvalidPathError{}}), do: false

  # Groups by reason for DB / HTTP transport errors
  def before_send(%{exception: [%{type: "DBConnection.ConnectionError"}], ...} = event) do
    %{event | fingerprint: ["db_connection", reason]}
  end
  def before_send(%{exception: [%{type: "Mint.TransportError"}], ...} = event) do
    %{event | fingerprint: ["mint_transport", reason]}
  end
  # ...
end
```

### Sentry context in LiveViews

LiveViews lack automatic Sentry context. Plausible adds it via a custom `on_mount` hook:

**`lib/plausible_web/live/sentry_context.ex` (70 lines):**

```elixir
defmodule PlausibleWeb.Live.SentryContext do
  def on_mount(:default, _params, _session, socket) do
    if Phoenix.LiveView.connected?(socket) do
      # Builds request context from connect_info
      Sentry.Context.set_request_context(request_context)
      # Sets user context if available
      if current_user = socket.assigns[:current_user] do
        Sentry.Context.set_user_context(%{id: current_user.id})
      end
    end
    {:cont, socket}
  end
end
```

Used via `use PlausibleWeb, :live_view` (which includes `use PlausibleWeb.Live.SentryContext`), with an opt-out via `use PlausibleWeb, live_view: :no_sentry_context`.

### Sentry in the Endpoint

**`lib/plausible_web/endpoint.ex` lines 3, 81:**

```elixir
use Sentry.PlugCapture       # Catches unhandled exceptions
plug(Sentry.PlugContext)     # Adds request context
```

### Sentry context in controllers

**`lib/plausible_web/plugs/auth_plug.ex` line 65:**

```elixir
Sentry.Context.set_user_context(%{id: user.id, name: user.name, email: user.email})
```

**`lib/plausible_web/plugs/authorize_site_access.ex` lines 106, 110:**

```elixir
Sentry.Context.set_user_context(%{id: current_user.id})
Sentry.Context.set_extra_context(%{site_id: site.id, domain: site.domain})
```

### Oban error reporting to Sentry

Oban errors are captured via telemetry and forwarded to both Logger and Sentry:

**`lib/oban_error_reporter.ex` (78 lines):**

```elixir
def handle_event([:oban, :job, :exception], measure, %{job: job} = meta) do
  extra = job |> Map.take([:id, :args, :meta, :queue, :worker]) |> Map.merge(measure)
  capture_error(meta, extra)
end

defp capture_error(meta, extra) do
  Logger.error(
    "Background job (#{inspect(extra)}) failed:\n\n  " <>
      Exception.format(:error, meta.reason, meta.stacktrace),
    crash_reason: {meta.reason, meta.stacktrace},
    sentry: %{extra: extra}
  )
end
```

Attached in `setup_sentry/0`:

**`lib/plausible/application.ex` lines 360–368:**

```elixir
def setup_sentry() do
  LoggerBackends.add(Sentry.LoggerBackend)

  :telemetry.attach_many(
    "oban-errors",
    [[:oban, :job, :exception], [:oban, :notifier, :exception], [:oban, :plugin, :exception]],
    &ObanErrorReporter.handle_event/4,
    %{}
  )
end
```

---

## 4. OpenTelemetry (Distributed Tracing)

### Dependencies

**`mix.exs` lines 110–128:**

```elixir
{:opentelemetry, "~> 1.7"},
{:opentelemetry_api, "~> 1.5"},
{:opentelemetry_api_experimental, git: ..., sparse: "apps/opentelemetry_api_experimental"},
{:opentelemetry_ecto, "~> 1.2"},
{:opentelemetry_exporter, "~> 1.10"},
{:opentelemetry_experimental, git: ..., sparse: "apps/opentelemetry_experimental"},
{:opentelemetry_phoenix, "~> 2.0.1"},
{:opentelemetry_oban, "~> 1.1"},
{:opentelemetry_cowboy, "~> 1.0"},
{:opentelemetry_semantic_conventions, "~> 1.27", override: true},
```

### OTLP Configuration

Honeycomb is the primary OTel backend. Config is conditional on both `HONEYCOMB_API_KEY` and `HONEYCOMB_DATASET` being set:

**`config/runtime.exs` lines 963–980:**

```elixir
if honeycomb_api_key && honeycomb_dataset do
  config :opentelemetry,
    resource: Plausible.OpenTelemetry.resource_attributes(runtime_metadata),
    span_processor: :batch,
    traces_exporter: :otlp

  config :opentelemetry_exporter,
    otlp_protocol: :grpc,
    otlp_endpoint: otlp_endpoint,
    otlp_headers: [
      {"x-honeycomb-team", honeycomb_api_key},
      {"x-honeycomb-dataset", honeycomb_dataset}
    ]
else
  config :opentelemetry,
    sampler: :always_off,
    traces_exporter: :none
end
```

OTLP endpoint defaults to Honeycomb's API:

**`config/runtime.exs` lines 265–266:**

```elixir
otlp_endpoint =
  get_var_from_path_or_env(config_dir, "OTLP_ENDPOINT", "https://api.honeycomb.io:443")
```

### OTel Setup in Application

**`lib/plausible/application.ex` lines 371–382:**

```elixir
defp setup_opentelemetry() do
  :opentelemetry_cowboy.setup()
  OpentelemetryPhoenix.setup(adapter: :cowboy2)
  OpentelemetryEcto.setup([:plausible, :repo], db_statement: :enabled)
  OpentelemetryEcto.setup([:plausible, :clickhouse_repo], db_statement: :enabled)
  OpentelemetryOban.setup()
  Plausible.OpenTelemetry.Logger.setup()

  if Application.get_env(:opentelemetry_experimental, :readers, []) != [] do
    Plausible.OpenTelemetry.BeamMetrics.setup()
  end
end
```

This instruments:

- **Cowboy** (HTTP server) via `:opentelemetry_cowboy`
- **Phoenix** router/controller via `OpentelemetryPhoenix`
- **Ecto** (both Postgres repo & Clickhouse repos) via `OpentelemetryEcto`
- **Oban** (background jobs) via `OpentelemetryOban`
- **Logger/trace correlation** via custom handler (see below)
- **BEAM metrics** (optional, see Section 5)

Database statements are enabled for tracing (`db_statement: :enabled`), meaning SQL queries appear in traces.

### Resource Attributes

**`lib/plausible/open_telemetry.ex` lines 54–62:**

```elixir
def resource_attributes(runtime_metadata) do
  [
    {"service.name", "analytics"},
    {"service.namespace", "plausible"},
    {"service.instance.app_host", runtime_metadata[:app_host]},
    {"service.instance.id", runtime_metadata[:host]},
    {"service.version", runtime_metadata[:version]}
  ]
end
```

### Custom span attributes

**`lib/plausible/open_telemetry.ex` lines 19–51:**

```elixir
def add_site_attributes(site) do
  Tracer.set_attributes([
    {"plausible.site.id", site.id},
    {"plausible.site.domain", site.domain},
    {"plausible.site.team_id", site.team_id}
  ])
end

def add_user_attributes(user) do
  Tracer.set_attributes([
    {"plausible.user.id", user.id},
    {"plausible.user.name", user.name},
    {"plausible.user.email", user.email}
  ])
end
```

### Logger / Trace Correlation

Extracts the current OTel trace_id and injects it into Logger metadata when a Phoenix router dispatch starts:

**`lib/plausible/open_telemetry/logger.ex` (34 lines):**

```elixir
defmodule Plausible.OpenTelemetry.Logger do
  def setup do
    :telemetry.attach(
      "plausible-otel-logger-metadata",
      [:phoenix, :router_dispatch, :start],
      &__MODULE__.handle_router_dispatch_start/4,
      %{}
    )
  end

  def handle_router_dispatch_start(_event, _measurements, _metadata, _config) do
    case Plausible.OpenTelemetry.current_trace_id() do
      nil -> :ok
      trace_id_hex -> Logger.metadata(trace_id: trace_id_hex)
    end
  end
end
```

This enables correlating log lines with distributed traces — the `trace_id` appears in JSON logs alongside `request_id`.

### Trace ID helper

**`lib/plausible/open_telemetry.ex` lines 6–17:**

```elixir
def current_trace_id do
  case Tracer.current_span_ctx() do
    :undefined -> nil
    span_ctx ->
      span_ctx
      |> OpenTelemetry.Span.trace_id()
      |> Integer.to_string(16)
      |> String.downcase()
  end
end
```

---

## 5. BEAM Process Metrics (OTel)

Optional, disabled by default (`BEAM_METRICS_ENABLED=false`).

### Configuration

**`config/runtime.exs` lines 982–1004:**

```elixir
beam_metrics_enabled? = get_bool_from_path_or_env(config_dir, "BEAM_METRICS_ENABLED", false)

if beam_metrics_enabled? do
  beam_metrics_interval = get_int_from_path_or_env(config_dir, "BEAM_METRICS_INTERVAL_MS", 5_000)

  beam_metrics_otlp_endpoint =
    get_var_from_path_or_env(config_dir, "OTEL_EXPORTER_OTLP_ENDPOINT") || otlp_endpoint

  config :opentelemetry_experimental,
    readers: [
      %{
        module: :otel_metric_reader,
        config: %{
          export_interval_ms: beam_metrics_interval,
          exporter:
            {:otel_exporter_metrics_otlp,
             %{
               endpoints: [beam_metrics_otlp_endpoint]
             }}
        }
      }
    ]
end
```

### Implementation

Uses `:recon.proc_count/2` to sample the top 20 processes by memory, reductions, and message queue length. Emits as OTel observable gauge observations:

**`lib/plausible/open_telemetry/beam_metrics.ex` (107 lines):**

```elixir
defmodule Plausible.OpenTelemetry.BeamMetrics do
  @top_n 20
  @metrics [:memory, :reductions, :message_queue_len]

  def setup do
    scope = :opentelemetry.instrumentation_scope("plausible_beam_metrics", "0.1.0", :undefined)
    meter = :opentelemetry_experimental.get_meter(scope)

    gauges =
      Enum.map(@metrics, fn metric ->
        {name, opts} = Map.fetch!(@instruments, metric)
        :otel_meter.create_observable_gauge(meter, name, opts)
      end)

    :otel_meter.register_callback(meter, gauges, &observe_top_processes/1, [])
  end

  def observe_top_processes(_callback_args) do
    Enum.map(@metrics, fn metric ->
      {gauge_name, _opts} = Map.fetch!(@instruments, metric)
      observations = collect_observations(metric)
      {gauge_name, observations}
    end)
  end
end
```

Defines three gauge instruments:

- `beam.top_process.memory` (bytes)
- `beam.top_process.reductions` (count)
- `beam.top_process.message_queue_len` (count)

Each observation includes process-level attributes: PID, registered name, current function, initial call.

---

## 6. PromEx / Prometheus (Application Metrics)

### Dependency

**`mix.exs` line 142–143:**

```elixir
{:prom_ex, "~> 1.8"},
{:peep, "~> 3.0"},
```

### Configuration

PromEx is **disabled by default** (`PROMEX_DISABLED=true`):

**`config/runtime.exs` lines 1008–1015:**

```elixir
promex_disabled? = get_bool_from_path_or_env(config_dir, "PROMEX_DISABLED", true)

config :plausible, Plausible.PromEx,
  disabled: promex_disabled?,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled
```

The metrics server is disabled (`metrics_server: :disabled`), meaning there's no built-in `/metrics` endpoint — they rely on external scraping (e.g., Prometheus operator). Grafana dashboard provisioning is also disabled.

### Custom Storage Adapter: `StripedPeep`

Adapters PromEx's metric collection to use `Peep` with `:striped` storage for better concurrency:

**`lib/plausible/prom_ex/striped_peep.ex` (25 lines):**

```elixir
defmodule Plausible.PromEx.StripedPeep do
  @behaviour PromEx.Storage

  def scrape(name) do
    (Peep.get_all_metrics(name) || [])
    |> Peep.Prometheus.export()
    |> IO.iodata_to_binary()
  end

  def child_spec(name, metrics) do
    Peep.child_spec(name: name, metrics: metrics, storage: :striped)
  end
end
```

Configured in `config/config.exs` line 81:

```elixir
config :prom_ex, :storage_adapter, Plausible.PromEx.StripedPeep
```

### Custom Bucket Calculator

**`lib/plausible/prom_ex/buckets.ex` (85 lines):** Implements `Peep.Buckets` behaviour, converting `PromEx`'s `reporter_options` bucket lists into balanced trees for the `Peep` storage engine.

Configured in `config/config.exs` line 82:

```elixir
config :peep, :bucket_calculator, Plausible.PromEx.Buckets
```

### PromEx Module and Plugins

**`lib/plausible/prom_ex.ex` (53 lines):**

```elixir
defmodule Plausible.PromEx do
  use PromEx, otp_app: :plausible

  @plugins [
    Plugins.Application,
    Plugins.Beam,
    Plugins.PhoenixLiveView,
    {Plugins.Phoenix, router: PlausibleWeb.Router, endpoint: PlausibleWeb.Endpoint},
    {Plugins.Ecto,
     repos: [
       Plausible.Repo,
       Plausible.ClickhouseRepo,
       Plausible.IngestRepo,
       Plausible.AsyncInsertRepo
     ]},
    Plausible.PromEx.Plugins.PlausibleMetrics
  ]
  # Oban is added to plugins in non-test environments
end
```

Standard PromEx metric groups:

| Plugin | Coverage |
|--------|----------|
| `Application` | VM metrics, total memory, etc. |
| `Beam` | BEAM metrics via `prom_ex` built-in |
| `PhoenixLiveView` | LiveView socket/channel metrics |
| `Phoenix` | HTTP request duration, status codes |
| `Ecto` | DB query duration, queue time (all 4 repos) |
| `Oban` | Job counts, execution times, failures |
| `PlausibleMetrics` | **Custom app metrics** (see Section 7) |

### PromEx Plug in Endpoint

**`lib/plausible_web/endpoint.ex` line 72:**

```elixir
plug(PromEx.Plug, prom_ex_module: Plausible.PromEx)
```

### Grafana Dashboards

**`lib/plausible/prom_ex.ex` lines 36–52:**

```elixir
def dashboard_assigns do
  [datasource_id: "grafanacloud-prom", default_selected_interval: "30s"]
end

def dashboards do
  [
    {:prom_ex, "application.json"},
    {:prom_ex, "beam.json"},
    {:prom_ex, "phoenix.json"},
    {:prom_ex, "ecto.json"},
    {:prom_ex, "oban.json"}
  ]
end
```

Five pre-defined dashboards for Grafana Cloud. However, `grafana: :disabled` in config means the automatic provisioning is turned off.

### Important: No LiveDashboard

Plausible does **not** use `Phoenix.LiveDashboard`. The `grep` for `LiveDashboard|live_dashboard` returned zero results.

---

## 7. Telemetry Events (Custom Instrumentation)

### `Plausible.PromEx.Plugins.PlausibleMetrics`

The primary custom PromEx plugin, defining both polling and event-driven metrics. Located at **`lib/plausible/telemetry/plausible_metrics.ex`** (384 lines).

#### Event Metrics (via Telemetry)

| Metric prefix | Event source | Type | Tags |
|---|---|---|---|
| `plausible.cache_warmer.sites.refresh.all` | `Site.Cache` refresh all | Distribution (ms) | — |
| `plausible.cache_warmer.sites.refresh.updated_recently` | `Site.Cache` refresh recent | Distribution (ms) | — |
| `plausible.cache_warmer.tracker_script.refresh.*` | TrackerScript cache refresh | Distribution (ms) | — |
| `plausible.ingest.events.pipeline.steps` | Ingestion pipeline step | Distribution (µs) | `:step` |
| `plausible.remote_ingest.events.pipeline.steps` | Remote relay pipeline step | Distribution (µs) | `:step` |
| `plausible.sessions.cache.register.lock` | Session cache lock acquisition | Distribution (µs) | — |
| `plausible.ingest.events.buffered.total` | Event buffered | Counter | — |
| `plausible.ingest.events.dropped.total` | Event dropped | Counter | `:reason` |
| `plausible.remote_ingest.events.buffered.total` | Remote event buffered | Counter | — |
| `plausible.remote_ingest.events.dropped.total` | Remote event dropped | Counter | `:reason` |
| `plausible.ingest.user_agent_parse.timeout.total` | UA parse timeout | Counter | — |
| `plausible.plausible_cache.hit` | ConCache hit | Counter | `:name` |
| `plausible.plausible_cache.miss` | ConCache miss | Counter | `:name` |
| `plausible.sessions.transfer.duration` | Session transfer | Distribution (µs) | — |
| `plausible.tracker_script.request.v2` | v2 tracker request | Counter | `:status` |
| `plausible.tracker_script.request.legacy` | Legacy tracker request | Counter | `:status` |
| `plausible.persistor.remote.request.*` | Remote persistor HTTP calls | Distribution (ms) | `:result`, `:path` |
| `plausible.persistor.remote.connect.*` | Remote persistor connect | Distribution (ms) | `:status` |
| `plausible.persistor.remote.send.*` | Remote persistor send | Distribution (ms) | `:status` |
| `plausible.persistor.remote.receive.*` | Remote persistor receive | Distribution (ms) | `:status` |
| `plausible.detection.success` | Installation detection success | Counter | — |
| `plausible.detection.failure` | Installation detection failure | Counter | — |

#### Polling Metrics

Two polling groups (every 5 seconds):

1. **Write buffer metrics** — message queue length for `Event.WriteBuffer` and `Session.WriteBuffer`
2. **Cache metrics** — size of user_agents, sessions, and sites caches

```elixir
def execute_write_buffer_metrics do
  # Queries GenServer message queue lengths via Process.info
  :telemetry.execute([:prom_ex, :plugin, :write_buffer_metrics, :events_message_queue_len],
    %{count: events_message_queue_len})
  :telemetry.execute([:prom_ex, :plugin, :write_buffer_metrics, :sessions_message_queue_len],
    %{count: sessions_message_queue_len})
end

def execute_cache_metrics do
  :telemetry.execute([:prom_ex, :plugin, :cache, :user_agents], %{count: ...})
  :telemetry.execute([:prom_ex, :plugin, :cache, :sessions], %{count: ...})
  :telemetry.execute([:prom_ex, :plugin, :cache, :sites], %{count: ...})
end
```

### Ingestion Persistor Telemetry

**`lib/plausible/ingestion/persistor/telemetry_handler.ex`** (177 lines): Listens to `Finch` telemetry events (`[:finch, :request, :stop]`, etc.) and re-emits them under `[:persistor, :remote, ...]` namespaces, but only for requests to the persistor host. This allows granular monitoring of the remote ingestion pipeline — connect, send, receive, total duration — all with status tagging.

### Query performance tracking

Notable: **`Plausible.Ingestion.Counters`** uses telemetry handlers to aggregate per-domain event counters for internal stats display (not exported to Prometheus).

**`lib/plausible/ingestion/counters/telemetry_handler.ex`** (65 lines): Subscribes to `[:plausible, :ingest, :event, ...]` events and updates in-memory counters for the dashboard.

### Telemetry events emitted by modules

The app emits telemetry events from multiple places using `:telemetry.execute`:

**`lib/plausible/ingestion/event.ex` lines 104–118:**
```elixir
:telemetry.execute(telemetry_ua_parse_timeout(), %{}, %{})
:telemetry.execute(telemetry_event_buffered(), %{}, %{domain: domain, ...})
:telemetry.execute(telemetry_event_dropped(), %{}, %{domain: domain, reason: reason, ...})
```

**`lib/plausible_web/plugs/tracker_plug.ex` lines 67–102:**
```elixir
:telemetry.execute(telemetry_event(:v2), %{}, %{status: status})
:telemetry.execute(telemetry_event(:legacy), %{}, %{status: status})
```

**`lib/plausible/session/transfer.ex` line 133:**
```elixir
:telemetry.execute(telemetry_event(), %{duration: System.monotonic_time() - started})
```

**`lib/plausible/session/cache_store.ex` line 25:**
```elixir
:telemetry.execute(@lock_telemetry_event, %{duration: lock_duration}, %{})
```

---

## 8. Health Checks

### Routes

Defined in **`lib/plausible_web/router.ex` lines 392–406**:

```elixir
scope "/api", PlausibleWeb do
  # Legacy (deprecated but kept for external checks)
  get "/health", Api.SystemController, :readiness

  scope "/system" do
    get "/", Api.SystemController, :info
    get "/health/live", Api.SystemController, :liveness
    get "/health/ready", Api.SystemController, :readiness
  end
end
```

### Liveness Probe

**`lib/plausible_web/controllers/api/system_controller.ex` lines 21–23:**

```elixir
def liveness(conn, _params) do
  json(conn, %{ok: true})
end
```

Simple: if the server is running, it returns `{"ok": true}`.

### Readiness Probe

**`lib/plausible_web/controllers/api/system_controller.ex` lines 25–92:**

Checks four subsystems in parallel with a 15-second timeout:

1. **Postgres** — `SELECT 1` query
2. **Clickhouse** — `SELECT 1` query
3. **Critical caches** — Checks `Site.Cache`, `Shield.IPRuleCache`, and `TrackerScript(ID)Cache` are all `ready?()`
4. **Session transfer** — Checks `Session.Transfer.attempted?()` (returns `"waiting"` until first transfer completes)

```elixir
@critical_caches [
  Plausible.Site.Cache,
  Plausible.Shield.IPRuleCache,
  on_ee do: Plausible.Site.TrackerScriptIdCache,
  else: Plausible.Site.TrackerScriptCache
]

def readiness(conn, _params) do
  # Parallel checks via Task.async
  postgres_health = Task.async(fn -> Ecto.Adapters.SQL.query(Plausible.Repo, "SELECT 1", []) end)
  clickhouse_health = Task.async(fn -> Ecto.Adapters.SQL.query(Plausible.ClickhouseRepo, "SELECT 1", []) end)

  # ... await tasks, evaluate cache + session health

  status = case {postgres_health, clickhouse_health, cache_health, sessions_health} do
    {"ok", "ok", "ok", "ok"} -> 200
    _ -> 500
  end

  put_status(conn, status) |> json(%{
    postgres: postgres_health,
    clickhouse: clickhouse_health,
    sites_cache: cache_health,
    sessions: sessions_health
  })
end
```

### Info Endpoint

**`lib/plausible_web/controllers/api/system_controller.ex` lines 6–19:**

Returns build metadata (version, commit, created, tags) and geolocation database type. Useful for identifying the running release.

---

## 9. Dependency Summary

| Purpose | Package | Version | Notes |
|---|---|---|---|
| Structured logging | `ex_json_logger` | ~> 1.4.0 | Optional JSON log format |
| Error tracking | `sentry` | ~> 11.0.4 | Custom Finch-based HTTP client |
| Error tracking helper | `logger_backends` | ~> 1.0.0 | Adds Sentry.LoggerBackend |
| Distributed tracing | `opentelemetry` | ~> 1.7 | Core OTel API |
| Distributed tracing | `opentelemetry_api` | ~> 1.5 | OTel API |
| Distributed tracing | `opentelemetry_exporter` | ~> 1.10 | OTLP gRPC exporter |
| OTel HTTP | `opentelemetry_cowboy` | ~> 1.0 | Cowboy instrumentation |
| OTel Phoenix | `opentelemetry_phoenix` | ~> 2.0.1 | Phoenix instrumentation |
| OTel Ecto | `opentelemetry_ecto` | ~> 1.2 | DB query tracing |
| OTel Oban | `opentelemetry_oban` | ~> 1.1 | Background job tracing |
| OTel Experimental | `opentelemetry_experimental` | git ref | Metric reader (BEAM metrics) |
| OTel Semantic Conv | `opentelemetry_semantic_conventions` | ~> 1.27 | Attribute naming |
| Prometheus metrics | `prom_ex` | ~> 1.8 | PromEx metrics framework |
| Metric storage | `peep` | ~> 3.0 | Thread-safe metric aggregation |
| HTTP client | `finch` | ~> 0.23 | Used by Sentry client |
| HTTP tracing | `opentelemetry_req` | ~> 1.0 | Req HTTP client tracing |
| Live monitoring | `observer_cli` | ~> 1.7 | CLI-based BEAM observer |
| Debug tools | `recon` | ~> 2.5 | BEAM introspection (used by BeamMetrics) |
| Clustering | `libcluster` | ~> 3.5 | Node discovery |
| **Not used** | `Phoenix.LiveDashboard` | — | Not present at all |
| **Not used** | `telemetry_metrics` | — | No `Telemetry.Metrics` definitions |
| **Not used** | `telemetry_metrics_prometheus` | — | Metrics via PromEx + Peep instead |

---

## Architecture Diagram

```mermaid
flowchart TB
    subgraph "Application Startup"
        A[Plausible.Application.start/2] --> B[setup_request_logging]
        A --> C[setup_sentry]
        A --> D[setup_opentelemetry]
        A --> E[Plausible.Ingestion.Persistor.TelemetryHandler.install]
    end

    subgraph "Logging"
        L1[Logger] --> L2[ex_json_logger<br/>JSON format]
        L1 --> L3[Sentry.LoggerBackend<br/>:error level]
    end

    subgraph "Sentry"
        S1[Sentry.PlugCapture] --> S2[Sentry DSN]
        S1 --> S3[Plausible.SentryFilter<br/>before_send]
        S4[Finch HTTP Client] --> S1
        S5[Sentry.PlugContext] --> S6[LiveView SentryContext<br/>on_mount]
    end

    subgraph "OpenTelemetry"
        O1[:opentelemetry_cowboy] --> O8[OTLP Exporter]
        O2[OpentelemetryPhoenix] --> O8
        O3[OpentelemetryEcto<br/>Repo + ClickhouseRepo] --> O8
        O4[OpentelemetryOban] --> O8
        O5[Plausible.OpenTelemetry.Logger<br/>trace_id -> Logger metadata] --> O8
        O6[Plausible.OpenTelemetry.BeamMetrics<br/>Top 20 processes] --> O9[otel_exporter_metrics_otlp]
        O7[Custom span attrs<br/>site.id, user.email] --> O8
    end

    subgraph "PromEx / Prometheus"
        P1[PromEx.Plug] --> P2[PromEx Modules]
        P2 --> P3[Plugins.Application]
        P2 --> P4[Plugins.Beam]
        P2 --> P5[Plugins.PhoenixLiveView]
        P2 --> P6[Plugins.Phoenix]
        P2 --> P7[Plugins.Ecto]
        P2 --> P8[Plugins.Oban]
        P2 --> P9[PlausibleMetrics<br/>Custom plugin]
        P9 --> P10[Polling: write buffers, cache sizes]
        P9 --> P11[Event: pipeline steps, drops, cache hits]
        P2 --> P12[StripedPeep storage]
    end

    subgraph "Telemetry Events"
        T1[Ingestion.Event] -->|buffered/dropped/ua_timeout| P9
        T2[TrackerPlug] -->|v2/legacy requests| P9
        T3[Session.Transfer] -->|duration| P9
        T4[Session.CacheStore] -->|lock duration| P9
        T5[Persistor TelemetryHandler] -->|remote HTTP via Finch| P9
        T6[Phoenix Endpoint :stop] -->|request logging| B
    end

    subgraph "Health Checks"
        H1[/api/system/health/live] --> H2[{"ok": true}]
        H3[/api/system/health/ready] --> H4[Postgres SELECT 1]
        H3 --> H5[Clickhouse SELECT 1]
        H3 --> H6[Cache ready?]
        H3 --> H7[Session transfer attempted?]
    end

    subgraph "Error Context in LiveViews"
        LSV[LiveView on_mount] --> LSC[Set request context]
        LSV --> LSU[Set user context]
    end
```

---

## Key Patterns Summary

1. **Conditional configuration** — Log format, OTel, PromEx, and BEAM metrics are all opt-in via env vars. Production defaults are safe (no external dependencies).

2. **Custom Sentry HTTP client** — Rather than using hackney (Sentry's default), Plausible routes all Sentry traffic through its own Finch pool. This means one fewer dependency and consistent connection management.

3. **Dual metrics path** — Both OTLP (Honeycomb) and Prometheus (PromEx) are supported simultaneously. OTel handles tracing (and optionally BEAM process metrics), PromEx handles application-level metrics (request rates, pipeline performance, cache efficiency).

4. **Trace-log correlation** — The `Plausible.OpenTelemetry.Logger` handler extracts the OTel trace_id and injects it into Logger metadata at router dispatch time. Combined with `ex_json_logger`, this produces JSON log lines with `trace_id` and `request_id` that can be correlated in Honeycomb, Grafana, etc.

5. **No Telemetry.Metrics definitions** — Unlike many Phoenix apps, Plausible doesn't use `Telemetry.Metrics` directly. All metrics are defined through PromEx's `Event.build` / `Polling.build` DSL, or through raw `:telemetry.execute` calls.

6. **Granular ingestion pipeline metrics** — The remote persistor telemetry handler decomposes Finch HTTP calls into connect/send/receive/total phases with status tagging, giving detailed visibility into the event forwarding pipeline.

7. **Polling-based process-level metrics** — The BEAM metrics module uses `:recon.proc_count` and OTel observable gauges to sample top BEAM processes — a custom implementation not commonly seen in Elixir apps.
