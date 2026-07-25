# Logflare Observability & Monitoring

> Logflare is a log management tool itself, so its own observability practices are especially relevant.

## 1. Telemetry Events

**File:** `lib/telemetry.ex` (609 lines)

The central telemetry supervisor — `Logflare.Telemetry` — is a `Supervisor` that:

1. Starts a `telemetry_poller` every 30s for periodic measurements
2. Optionally starts an `OtelMetricExporter` when OpenTelemetry is enabled

It defines a massive `metrics/0` function returning ~100+ `Telemetry.Metrics` definitions organized into groups.

### Metric groups defined

| Group | Prefix/Source | Lines |
|-------|---------------|-------|
| **Phoenix** | `phoenix.endpoint.stop.duration`, `phoenix.router_dispatch.stop.duration` | 117-119 |
| **Database** | `logflare.repo.query.*` — total/query/queue/idle time | 122-136 |
| **VM / System** | `vm.memory.total`, `vm.total_run_queue_lengths.*`, `logflare.system.observer.metrics.*` (30+ metrics covering uptime, run queue, IO, processes, atoms, ports, ETS, memory breakdowns, scheduler utilization) | 139-171 |
| **Broadway** | `broadway.batcher.stop.duration`, `broadway.batch_processor.stop.duration`, etc. | 173-178 |
| **Cachex** | `cachex.*.{purge,stats,evictions,...}` — conditionally enabled via `cache_stats?` config flag | 96-114 |
| **Application** | `logflare.logs.processor.ingest.*`, `logflare.backends.*`, `logflare.rate_limiter.*`, `logflare.ingest.*`, `logflare.system.finch.*`, `logflare.context_cache_gossip.*`, `logflare.ingest_event_queue.*` | 180-411 |
| **Finch HTTP** | `finch.request.stop.duration`, `finch.connect.stop.duration`, `finch.queue.stop.duration` | 414-434 |

### Periodic measurement functions

```elixir
# lib/telemetry.ex:447-465
defp periodic_measurements do
  cachex_metrics =
    if cache_stats? do
      [{__MODULE__, :cachex_metrics, []}]
    else
      []
    end

  process_metrics = [
    {__MODULE__, :process_message_queue_metrics, []},
    {__MODULE__, :process_memory_metrics, []},
    {__MODULE__, :ets_table_metrics, []}
  ]

  cachex_metrics ++ process_metrics
end
```

Key periodic data collectors:
- **`process_message_queue_metrics/0`** — uses `:recon.proc_count(:message_queue_len, 10)` to get top-10 processes by mailbox depth (line 494)
- **`process_memory_metrics/0`** — uses `:recon.proc_count(:memory, 10)` for top-10 by memory (line 496)
- **`ets_table_metrics/0`** — scans all ETS tables, sorts by memory, emits individual (top 10) and grouped (top 100) metrics (lines 555-576)
- **`cachex_metrics/0`** — reads Cachex stats and emits via `:telemetry.execute([:cachex, metric], metrics)` (lines 467-491)

### How telemetry events are emitted across the codebase

The codebase has **52 call sites** for `:telemetry.execute/3` and `:telemetry.span/3`. Key patterns:

**Log ingestion (`lib/logflare/logs/processor.ex:31-57`):**
```elixir
:telemetry.span([:logflare, :logs, :processor, :ingest], metadata, fn ->
  batch = :telemetry.span([:logflare, :logs, :processor, :ingest, :handle_batch], metadata, fn ->
    {processor.handle_batch(data, source), metadata}
  end)

  :telemetry.execute(
    [:logflare, :logs, :processor, :ingest, :logs],
    %{count: length(batch)},
    metadata
  )

  :telemetry.span([:logflare, :logs, :processor, :ingest, :store], metadata, fn ->
    result = Backends.ingest_logs(batch, source, nil, true)
    {{result, new_meta}, new_meta}
  end)
end)
```

**Ingest drop/reject telemetry (`lib/logflare/backends.ex:1281-1289`):**
```elixir
defp emit_ingest_telemetry(tally, source) do
  for {reason, count} <- tally do
    :telemetry.execute(
      [:logflare, :logs, :ingest_logs, reason],
      %{count: count},
      %{source_id: source.id, source_token: source.token}
    )
  end
end
```

**Spool backends telemetry** (`lib/logflare/backends.ex`, `lib/logflare/backends/spool/*.ex`) — extensive counters for storage operations (S3/GCS puts, gets, queue pub/sub, ack/nack, batch outcomes, throttle states).

**Cache gossip telemetry** (`lib/logflare/context_cache/gossip.ex:23-96`) — has its own Telemetry handler for logging:
```elixir
@telemetry_handler_id "context-cache-gossip-logger"

def attach_logger do
  events = [
    [:logflare, :context_cache_gossip, :multicast, :stop],
    [:logflare, :context_cache_gossip, :receive, :stop]
  ]
  :telemetry.attach_many(@telemetry_handler_id, events, &__MODULE__.handle_telemetry_event/4, [])
end
```

---

## 2. Logging Configuration

### Logger base config (`config/config.exs:80-95`)

```elixir
config :logger,
  handle_otp_reports: true,
  handle_sasl_reports: false,
  level: :info

config :logger, :default_handler,
  config: %{
    sync_mode_qlen: 10_000,
    drop_mode_qlen: 10_000,
    flush_qlen: 20_000
  }
```

### Structured JSON logging with logger_json (`config/config.exs:92-95`)

```elixir
config :logger_json, :backend,
  metadata: :all,
  json_encoder: Jason,
  formatter: LoggerJSON.Formatters.GoogleCloudLogger
```

Uses **Google Cloud Logger format** — all metadata included, Jason for encoding. The `logger_json` backend is added dynamically at runtime (see below).

### Runtime logger level (`config/runtime.exs:198-209`)

```elixir
log_level =
  case String.downcase(System.get_env("LOGFLARE_LOG_LEVEL") || "") do
    "warn" -> :warning
    "warning" -> :warning
    "info" -> :info
    "debug" -> :debug
    "error" -> :error
    _ -> nil
  end

config :logger, filter_nil_kv_pairs.(level: log_level)
```

### Dynamic backend loading (`lib/logflare/application.ex:158-173`)

```elixir
defp add_logger_backends do
  for backend <- Application.get_env(:logflare, :logger_backends, []) do
    {:ok, _pid} = LoggerBackends.add(backend)
  end
end
```

Backends are activated based on runtime env vars in `config/runtime.exs:187-196`:

```elixir
config :logflare,
  :logger_backends,
  [
    if(System.get_env("LOGFLARE_LOGGER_BACKEND_URL") != nil,
      do: LogflareLogger.HttpBackend,
      else: nil
    ),
    if(Env.get_boolean("LOGFLARE_LOGGER_JSON"), do: LoggerJSON, else: nil)
  ]
  |> Enum.filter(&(&1 != nil))
```

This means at runtime:
- If `LOGFLARE_LOGGER_BACKEND_URL` is set → add `LogflareLogger.HttpBackend` (sends logs back to itself)
- If `LOGFLARE_LOGGER_JSON` is `true` → add `LoggerJSON` (structured JSON logging)

### Global logger metadata (`lib/logflare/application.ex:140-156`)

```elixir
def global_logger_metadata do
  [logflare_version: Application.spec(:logflare, :vsn) |> to_string()]
  |> Keyword.merge(Application.get_env(:logflare, :metadata, []))
  |> Map.new()
end

defp set_global_logger_metadata do
  :logger.update_primary_config(%{metadata: global_logger_metadata()})
end
```

Every log event automatically carries `logflare_version` and any configured `:metadata` (e.g., `cluster`).

### Log level filtering in tests (`config/test.exs:46-70`)

Filters out noisy Finch disconnections and DB connection failures:

```elixir
config :logger,
  default_handler: [
    filters: [
      {:finch_silencer, {&LogflareTest.LogFilters.ignore_finch_disconnections/2, []}},
      {:db_conn_silencer, {&LogflareTest.LogFilters.ignore_db_connection_failures/2, []}}
    ],
    level: :error
  ]
```

---

## 3. Custom Logger Backend (`logflare_logger_backend`)

**Dependency:** `{:logflare_logger_backend, github: "Logflare/logflare_logger_backend", ref: "b257399"}`

This is Logflare's own Logger backend that sends logs from an Elixir app into Logflare itself (dogfooding). Key components:

### HttpBackend (`LogflareLogger.HttpBackend`)

- Implements `:gen_event` behaviour
- Batches log events in an ETS table (`:logflare_logger_table`) and flushes periodically
- Configuration via app env or system env vars: `url`, `api_key`, `source_id`, `level`, `flush_interval`, `max_batch_size`
- Default API URL: `https://api.logflare.app`
- Handles `:flush`, `:in_flight_check` messages for reliability

### Formatter (`LogflareLogger.Formatter`)

Converts Logger events to Logflare's log format (BERT-encoded typically):

```elixir
def format(level, message, ts, metadata) do
  LogParams.encode(ts, level, message, metadata)
end
```

### LogParams (`LogflareLogger.LogParams`)

Handles serialization with type coercions (atoms → strings, pids → strings, keywords → maps, structs → maps). Includes VM context enrichment:

```elixir
def enrich(context, :vm) do
  Map.merge(context, %{"vm" => %{"node" => "#{Node.self()}"}})
end
```

### Runtime prod config (`config/prod.exs:28-31`)

```elixir
config :logflare_logger_backend,
  flush_interval: 2_000,
  max_batch_size: 250
```

---

## 4. User-Specific Log Routing (UserMonitoring)

**File:** `lib/logflare/backends/user_monitoring.ex`

This is a unique pattern: Logflare intercepts its own application logs and redirects them to the user's **System Source** when the user has enabled system monitoring.

### Log interceptor (`lib/logflare/application.ex:158-167`)

```elixir
defp start_user_log_interceptor do
  if Application.get_env(:logflare, :env) == :test do
    :ok
  else
    :logger.add_primary_filter(
      :user_log_intercetor,
      {&UserMonitoring.log_interceptor/2, []}
    )
  end
end
```

### Interceptor logic (`lib/logflare/backends/user_monitoring.ex:93-113`)

```elixir
def log_interceptor(%{meta: %{user_id: user_id} = meta} = log_event, _)
    when is_integer(user_id) do
  with %{system_monitoring: true} <- Users.Cache.get(user_id),
       %Sources.Source{} = source <- get_system_source_logs(user_id) do
    log_event.level
    |> LogflareLogger.Formatter.format(format_message(log_event), get_datetime(), meta)
    |> List.wrap()
    |> Processor.ingest(Logflare.Logs.Raw, source)
    :ignore
  else
    _ -> :ignore
  end
end
```

So user-specific logs are captured, formatted using the same `LogflareLogger.Formatter`, and re-ingested into the user's system source — all without blocking the original event.

### User metrics pipeline (`lib/logflare/backends/user_monitoring/ingest_pipeline.ex`)

A Broadway pipeline that pulls metrics from `OtelMetricExporter` and routes them per-user into system sources:

```elixir
def ingest_grouped_metrics({user_id, user_events}) do
  with %Sources.Source{} <-
         Sources.Cache.get_by(user_id: user_id, system_source_type: :metrics) do
    Processor.ingest(user_events, Raw, source)
  end
end
```

---

## 5. OpenTelemetry / Tracing

### Dependencies (`mix.exs:259-267`)

```elixir
{:opentelemetry, "~> 1.3"},
{:opentelemetry_api, "~> 1.2"},
{:opentelemetry_exporter, "~> 1.6"},
{:opentelemetry_phoenix, "~> 2.0.0-rc.2"},
{:opentelemetry_bandit, "~> 0.2.0-rc.1"},
{:otel_metric_exporter,
 git: "https://github.com/supabase/elixir-otel-metric-exporter", ref: "2a6de91"},
```

Uses the **Supabase fork** of `otel_metric_exporter` for OTel metrics export — notable because it enables pull-mode metrics.

### Disabled by default (`config/config.exs:172-175`)

```elixir
config :opentelemetry,
  sdk_disabled: true,
  span_processor: :batch,
  traces_exporter: :none
```

### Enabled at runtime via `LOGFLARE_OTEL_ENDPOINT` (`config/runtime.exs:424-478`)

```elixir
if System.get_env("LOGFLARE_OTEL_ENDPOINT") do
  config :logflare,
    opentelemetry_enabled?: true,
    ingest_sample_ratio: ingest_sample_ratio,
    endpoint_sample_ratio: endpoint_sample_ratio

  config :opentelemetry,
    sdk_disabled: false,
    traces_exporter: :otlp,
    resource: logflare_trace_metadata,
    sampler: {:parent_based, %{root: {LogflareWeb.OpenTelemetrySampler, %{probability: ...}}}}

  config :opentelemetry_exporter,
    otlp_protocol: :http_protobuf,
    otlp_endpoint: System.get_env("LOGFLARE_OTEL_ENDPOINT"),
    otlp_compression: :gzip,
    otlp_headers: [
      {"x-source", ...},
      {"x-api-key", ...}
    ]
end
```

### OTel setup at startup (`lib/logflare/application.ex:43-46`)

```elixir
if Application.get_env(:logflare, :opentelemetry_enabled?) do
  OpentelemetryBandit.setup()
  OpentelemetryPhoenix.setup(adapter: :bandit)
end
```

### Custom OpenTelemetry Sampler (`lib/logflare_web/open_telemetry_sampler.ex`)

Implements `:otel_sampler` behaviour with separate sampling ratios for:
- **Ingest routes** (`/logs`, `/api/logs`, `/api/events`)
- **Endpoint routes** (`/endpoints/query`, `/api/endpoints/query`)
- All other routes use the default probability

Also redacts `api_key` from URL query parameters in span attributes:

```elixir
if url_query =~ "api_key=" do
  replaced = url_query |> String.replace(~r/api_key=[^&]*/, "api_key=[REDACTED]")
  {decision, [{:"url.query", replaced}] ++ extra_attrs, tracestate}
end
```

### OTLP Ingest Endpoints (`lib/logflare_web/router.ex:542-565`)

Logflare itself receives OTLP traces, metrics, and logs via protobuf:

```elixir
scope "/v1", LogflareWeb do
  pipe_through([:ingest_otlp_api])
  post("/traces", LogController, :otel_traces, assigns: %{protobuf_schema: ExportTraceServiceRequest})
  post("/metrics", LogController, :otel_metrics, assigns: %{protobuf_schema: ExportMetricsServiceRequest})
  post("/logs", LogController, :otel_logs, assigns: %{protobuf_schema: ExportLogsServiceRequest})
end
```

### OTel Metric Export in Telemetry Supervisor (`lib/telemetry.ex:35-48`)

When `opentelemetry_enabled?`, the telemetry supervisor starts `OtelMetricExporter` with all the metric definitions:

```elixir
otel_exporter_opts =
  Application.get_all_env(:opentelemetry_exporter)
  |> Keyword.put(:metrics, metrics())
  |> Keyword.put(:resource, resource())
  |> Keyword.update!(:otlp_headers, &Map.new/1)
  |> Keyword.put(:otlp_concurrent_requests, max(base * 4, 50))
  |> Keyword.put(:spawn_opt, fullsweep_after: 10_000)
  |> Keyword.put(:hibernate_after, 5_000)

[{OtelMetricExporter, otel_exporter_opts}]
```

### Resource attributes (`lib/telemetry.ex:61-68`)

```elixir
def resource do
  %{
    name: "Logflare",
    service: service_attributes(System.get_env("LOGFLARE_COMMIT_SHA")),
    node: inspect(Node.self()),
    cluster: Application.get_env(:logflare, :metadata)[:cluster]
  }
end
```

---

## 6. System Metrics Collection

### SystemMetricsSup (`lib/logflare/system_metrics/system_metrics_sup.ex`)

A supervisor running under the main application tree that starts:

- `SystemMetrics.AllLogsLogged` — ETS-based counter of total logs ingested, persisted to Postgres every 5s per node
- `SystemMetrics.AllLogsLogged.Poller` — 1s poller tracking logs/second rate
- `telemetry_poller` dispatching every 30s:
  - `Observer.dispatch_stats/0` — VM metrics (run queue, IO, processes, atoms, ports, ETS, memory)
  - `Cluster.dispatch_stats/0` — cluster size monitoring
  - `SystemMetrics.Schedulers.async_dispatch_stats/0` — per-scheduler CPU utilization
  - `Cluster.finch/0` — HTTP connection pool status

### Observer (`lib/logflare/system_metrics/observer.ex`)

Emits comprehensive VM metrics via `:telemetry.execute`:

```elixir
defp get_metrics do
  {{:input, input}, {:output, output}} = :erlang.statistics(:io)
  {uptime, _} = :erlang.statistics(:wall_clock)
  %{
    uptime: uptime,
    run_queue: :erlang.statistics(:total_run_queue_lengths_all),
    io_input: input, io_output: output,
    logical_processors: ..., atom_limit: ..., atom_count: ...,
    process_limit: ..., process_count: ..., port_limit: ..., port_count: ...,
    ets_limit: ..., ets_count: ..., total_active_tasks: ...
  }
end
```

### Scheduler Utilization (`lib/logflare/system_metrics/schedulers/schedulers.ex`)

Measures per-core CPU utilization by sampling scheduler wall time:

```elixir
:erlang.system_flag(:scheduler_wall_time, true)
prev_sample = :scheduler.get_sample_all()
Process.sleep(duration)
next_sample = :scheduler.get_sample_all()
:erlang.system_flag(:scheduler_wall_time, false)
utilization = :scheduler.utilization(prev_sample, next_sample)
Enum.each(utilization, fn x ->
  :telemetry.execute(
    [:logflare, :system, :scheduler],
    %{utilization: Kernel.floor(util * 100)},
    %{name: ..., type: ...}
  )
end)
```

### ETS Table Monitoring (`lib/telemetry.ex:555-601`)

Scans all ETS tables, sorts by memory using `:recon_lib.sublist_top_n_attrs`, emits both individual (top 10) and grouped metrics.

---

## 7. Health Checks

**Routes:** `GET /health` (`lib/logflare_web/router.ex:440-443`)

**Controller:** `lib/logflare_web/controllers/health_check_controller.ex` (94 lines)

```elixir
def check(conn, _params) do
  repo_uptime = Logflare.Repo.get_uptime()
  caches = check_caches()
  memory_utilization = System.memory_utilization()
  max_memory_ratio = Application.get_env(:logflare, :health) |> Keyword.get(:memory_utilization)

  common_checks_ok? = [
    Sources.ingest_ets_tables_started?(),
    repo_uptime > 0,
    Enum.all?(Map.values(caches), &(&1 == :ok)),
    memory_utilization < max_memory_ratio
  ] |> Enum.all?()
  ...
end
```

Checks performed:
1. **ETS tables** for ingest are started
2. **Postgres reachable** (via `SELECT 1` wrapped in `repo.get_uptime`)
3. **All caches healthy** (Cachex `size()` call on all context caches + `LogEvents.Cache`)
4. **Memory utilization** below threshold (default: `0.95` via `LOGFLARE_HEALTH_MAX_MEMORY_UTILIZATION`)

Response payload includes: `status`, `proc_count`, `this_node`, `nodes`, `nodes_count`, `repo_uptime`, `caches`, `memory_utilization`.

For Supabase mode, additionally checks that all Supabase sources are seeded.

---

## 8. LiveDashboard

**Route:** `/admin/livedashboard` (`lib/logflare_web/router.ex:402`)

```elixir
scope "/admin", LogflareWeb do
  pipe_through([:browser, :require_auth, :check_admin])
  ...
  live_dashboard("/livedashboard", ecto_repos: [], metrics: Logflare.Telemetry)
end
```

- Mounted under admin section, requires authentication + admin check
- No Ecto repos displayed (user-facing DB not exposed)
- **Metrics powered by `Logflare.Telemetry`** — the same 100+ metrics from the telemetry supervisor feed the dashboard
- Enabled by env var: `LOGFLARE_ENABLE_LIVE_DASHBOARD` (`config/runtime.exs:141`)

---

## 9. Erlang System Monitor

**File:** `lib/logflare/erl_sys_mon.ex` (81 lines)

A GenServer that subscribes to Erlang VM system monitoring events:

```elixir
def init(_args) do
  :erlang.system_monitor(self(), [
    :busy_dist_port,
    :busy_port,
    {:long_gc, 1000},
    {:long_schedule, 500},
    {:long_message_queue, {0, 1_000}}
  ])
  :net_kernel.monitor_nodes(true, %{nodedown_reason: true})
  {:ok, []}
end
```

Warns via `Logger.warning` on:
- Long garbage collections (>1000ms)
- Long scheduler waits (>500ms)  
- Processes with >1000 messages in their mailbox
- Busy distribution ports
- Node up/down events (with nodedown reasons)

Allows runtime log level adjustment per process via `set_log_level/1`.

---

## 10. Observer CLI & Wobserver

### observer_cli (`mix.exs:128`)

```elixir
{:observer_cli, "~> 1.5"},
```

Provides CLI-based observer access in production (like `:observer` but terminal-based).

### Wobserver helpers (`lib/logflare/system_metrics/wobserver/`)

Custom modules for process inspection and JSON encoding (adapted from the wobserver library):
- `Helper` — JSON encoding for PIDs, Ports, References; parallel map
- `Processes` — process info, summaries, stack/state inspection

---

## 11. SIGTERM Handling

**File:** `lib/sig_term_handler.ex`

Swapped in at startup (`lib/logflare/application.ex:32-37`):

```elixir
:gen_event.swap_sup_handler(
  :erl_signal_server,
  {:erl_signal_handler, []},
  {Logflare.SigtermHandler, []}
)
```

Logs warnings on SIGTERM/SIGQUIT, disconnects from cluster, waits for configurable grace period (`sigterm_shutdown_grace_period_ms`, default 15s), then calls `System.stop()`.

---

## 12. Data Redaction in Logs

**File:** `lib/logflare/utils.ex:385-414`

Custom `Inspect.Opts.default_inspect_fun` that redacts sensitive fields when printing structs:

- `Backend` → strips `config`, `config_encrypted`
- `User` → strips `api_key`, `old_api_key`
- `OauthAccessToken` / `PartnerOauthAccessToken` → strips `token`
- `Tesla.Env` / `Tesla.Client` → redacted (inspect skipped in dev/test)

This prevents accidental leakage of secrets in log messages, error reports, and IEx.

---

## 13. Stripe Webhook Secret Warning

**File:** `lib/logflare/application.ex:132-138`

```elixir
defp warn_if_stripe_webhook_secret_unset do
  unless Application.get_env(:logflare, :stripe_webhook_secret) do
    Logger.warning("STRIPE_WEBHOOK_SECRET is not set — all Stripe webhook requests will be rejected")
  end
end
```

---

## Key Takeaways for Our Project

| Pattern | Logflare Approach |
|---------|------------------|
| **Telemetry metrics** | Central `Logflare.Telemetry` supervisor with 100+ `Telemetry.Metrics` definitions; emitted ad-hoc via `:telemetry.execute/3` throughout codebase |
| **Metric export** | OTLP exporter (HTTP Protobuf) to arbitrary endpoint; also OtelMetricExporter (Supabase fork) for pull-mode metrics |
| **Structured logging** | `logger_json` + Google Cloud Logger format; dynamic backend loading at runtime |
| **Self-monitoring** | `UserMonitoring.log_interceptor/2` — captures own logs matching a user_id and re-ingests into user's system source |
| **Tracing** | OpenTelemetry with custom sampler per route category; `api_key` redaction in span attributes |
| **Health checks** | Single `GET /health` endpoint checking Postgres, ETS, caches, memory |
| **Dashboard** | LiveDashboard at `/admin/livedashboard` with auth, fed by same Telemetry.Metrics definitions |
| **VM monitoring** | `ErlSysMon` GenServer for GC/long-schedule/mailbox alerts; `SystemMetricsSup` poller for comprehensive VM stats |
| **Cluster awareness** | `libcluster` + `Cluster.dispatch_stats/0` checks cluster size vs minimum |
| **Secrets handling** | Custom inspect function redacting API keys, OAuth tokens, backend configs from all log output |
