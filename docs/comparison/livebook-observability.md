# Livebook Observability Patterns

> Livebook v0.20.0-dev — the Elixir interactive notebook server.
> This document surveys how Livebook handles telemetry, logging, metrics, health checks, and APM.

---

## 1. Telemetry

### 1.1 Telemetry Supervisor

`lib/livebook_web/telemetry.ex` defines a Supervisor that starts a `telemetry_poller` process:

```elixir
# lib/livebook_web/telemetry.ex (lines 1-19)
defmodule LivebookWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
```

Started in `lib/livebook/application.ex` (line 27):

```elixir
LivebookWeb.Telemetry,
```

### 1.2 Defined Metrics

`lib/livebook_web/telemetry.ex` (lines 22-38):

```elixir
def metrics do
  [
    # Phoenix Metrics
    summary("phoenix.endpoint.stop.duration",
      unit: {:native, :millisecond}
    ),
    summary("phoenix.router_dispatch.stop.duration",
      tags: [:route],
      unit: {:native, :millisecond}
    ),

    # VM Metrics
    summary("vm.memory.total", unit: {:byte, :kilobyte}),
    summary("vm.total_run_queue_lengths.total"),
    summary("vm.total_run_queue_lengths.cpu"),
    summary("vm.total_run_queue_lengths.io")
  ]
end
```

Only **Phoenix endpoint/router** and **VM metrics**. No custom application-level telemetry events.

### 1.3 Periodic Measurements Are Stubbed

```elixir
# lib/livebook_web/telemetry.ex (lines 41-47)
defp periodic_measurements do
  [
    # A module, function and arguments to be invoked periodically.
    # This function must call :telemetry.execute/3 and a metric must be added above.
    # {LivebookWeb, :count_users, []}
  ]
end
```

The `periodic_measurements/0` callback returns an empty list. No custom `:telemetry.execute/3` calls exist in the codebase.

### 1.4 Plug Telemetry

`lib/livebook_web/endpoint.ex` (line 65):

```elixir
plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
```

Standard Phoenix endpoint telemetry, emitting `[:phoenix, :endpoint, :start|stop|exception]` events.

---

## 2. Logging

### 2.1 Default Logger Configuration (Compile-Time)

**`config/config.exs`** (lines 12-15):

```elixir
# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:request_id]
```

**`config/prod.exs`** (line 15):

```elixir
config :logger, level: :warning
```

**`config/dev.exs`** (lines 69-71):

```elixir
config :logger, :default_formatter,
  format: "$metadata[$level] $message\n",
  metadata: []
```

**`config/test.exs`** (lines 14, 21-29):

```elixir
config :logger, :default_handler, level: :warning

# Also configure the JSON formatter for test.
config :livebook, :logger, [
  {:handler, :json_log, :logger_std_h,
   %{
     config: %{file: ~c"tmp/test.log.json"},
     formatter:
       {LoggerJSON.Formatters.Basic,
        %{metadata: [:request_id, :users, :session_mode, :code, :event]}}
   }}
]
```

### 2.2 Runtime Logger Configuration (Environment-Driven)

Configured in `Livebook.config_runtime/0` (`lib/livebook.ex`, lines 99-119):

```elixir
if level = Livebook.Config.log_level!("LIVEBOOK_LOG_LEVEL") do
  config :logger, level: level
end

log_metadata = Livebook.Config.log_metadata!("LIVEBOOK_LOG_METADATA")
log_format = Livebook.Config.log_format!("LIVEBOOK_LOG_FORMAT") || :text

config :livebook, :log_format, log_format

case {log_format, log_metadata} do
  {:json, log_metadata} ->
    config :logger, :default_handler,
      formatter: {LoggerJSON.Formatters.Basic, %{metadata: log_metadata || [:request_id]}}

  {:text, log_metadata} when not is_nil(log_metadata) ->
    config :logger, :default_formatter, metadata: log_metadata

  _ ->
    :ok
end
```

Key environment variables:

| Env var | Values | Effect |
|---|---|---|
| `LIVEBOOK_LOG_LEVEL` | `error`, `warning`, `notice`, `info`, `debug` | Sets logger level |
| `LIVEBOOK_LOG_FORMAT` | `text` (default), `json` | Switches formatter to `LoggerJSON.Formatters.Basic` |
| `LIVEBOOK_LOG_METADATA` | Comma-separated keys (e.g., `users,code,session_mode,event`) | Controls which metadata keys are included |

### 2.3 Config Parsing Functions

`lib/livebook/config.ex` (lines 477-515):

```elixir
def log_level!(env) do
  levels = ~w(error warning notice info debug)
  if level = System.get_env(env) do
    if level in levels do
      String.to_atom(level)
    else
      abort!("expected #{env} to be one of #{Enum.join(levels, ", ")}, got: #{inspect(levels)}")
    end
  end
end

def log_metadata!(env) do
  if metadata = System.get_env(env) do
    for item <- String.split(metadata, ","),
        key = String.trim(item),
        do: String.to_atom(key)
  end
end

def log_format!(env) do
  formats = ~w(text json)
  if format = System.get_env(env) do
    if format in formats do
      String.to_atom(format)
    else
      abort!("expected #{env} to be one of #{Enum.join(formats, ", ")}, got: #{inspect(format)}")
    end
  end
end
```

### 2.4 Logger Handler Initialization

`lib/livebook/application.ex` (line 9):

```elixir
Logger.add_handlers(:livebook)
```

This loads all handlers configured under the `:livebook` OTP app, including any JSON handlers defined in `config :livebook, :logger, [...]`.

### 2.5 Structured Logging for Code Evaluation

`lib/livebook/session.ex` (lines 2787-2820) — every code evaluation triggers **two** log entries:

```elixir
defp log_code_evaluation(cell, state) do
  session_mode = state.data.mode

  evaluation_users =
    case session_mode do
      :default -> Map.values(state.data.users_map)
      :app -> if(state.deployed_by, do: [state.deployed_by], else: [])
    end

  # Legacy format (deprecated, kept for backward compatibility)
  Logger.info(
    ["Evaluating code\n  Session mode: #{session_mode}\n  Code: ", inspect(cell.source, printable_limit: :infinity)],
    Livebook.Utils.logger_users_metadata(evaluation_users)
  )

  # Structured format with searchable metadata
  Logger.info(
    "Evaluating code",
    Keyword.merge(
      Livebook.Utils.logger_users_metadata(evaluation_users),
      session_mode: session_mode,
      code: cell.source,
      event: "code.evaluate"
    )
  )
end
```

When `LIVEBOOK_LOG_FORMAT=json` is set, the structured call becomes a JSON log like:

```json
{
  "message": "Evaluating code",
  "time": "2025-10-06T19:19:40.131Z",
  "metadata": {
    "code": "1 + 1",
    "event": "code.evaluate",
    "users": [{"id": "1", "name": "Hugo Baraúna", "email": "alice@email.com"}],
    "session_mode": "default"
  },
  "severity": "info"
}
```

### 2.6 User Metadata in Logs

`lib/livebook/utils.ex` (lines 976-990):

```elixir
def logger_users_metadata(users) when is_list(users) do
  list =
    for user <- users do
      for key <- [:id, :name, :email],
          value = Map.get(user, key),
          do: {key, value},
          into: %{}
    end

  case Application.get_env(:livebook, :log_format) do
    :text -> [users: inspect(list)]
    :json -> [users: list]
  end
end
```

The formatter differs by format: JSON mode emits a list of maps, text mode uses `inspect(list)`.

User metadata is attached to logs via `Logger.metadata/1` in two places:

1. **UserPlug** (`lib/livebook_web/plugs/user_plug.ex`, line 89):
   ```elixir
   Logger.metadata(Livebook.Utils.logger_users_metadata([current_user]))
   ```

2. **UserHook** (`lib/livebook_web/live/hooks/user_hook.ex`, line 28):
   ```elixir
   Logger.metadata(Livebook.Utils.logger_users_metadata([socket.assigns.current_user]))
   ```

### 2.7 Request ID Metadata

`lib/livebook_web/endpoint.ex` (line 64):

```elixir
plug Plug.RequestId
```

`request_id` is the only metadata key included in the default logger configuration (`config/config.exs` line 15). It also serves as the fallback when JSON format is enabled but no `LIVEBOOK_LOG_METADATA` is specified (`lib/livebook.ex` line 112).

### 2.8 Runtime Log Forwarding (LoggerGLHandler)

`lib/livebook/runtime/erl_dist/logger_gl_handler.ex` — custom Erlang logger handler that forwards logs from notebook runtime (evaluator) nodes back to the main process:

```elixir
defmodule Livebook.Runtime.ErlDist.LoggerGLHandler do
  def log(%{meta: meta} = event, %{formatter: {formatter_module, formatter_config}}) do
    message = apply(formatter_module, :format, [event, formatter_config])
    if Livebook.Runtime.Evaluator.IOProxy.io_proxy?(meta.gl) do
      async_io(meta.gl, message)
    else
      send(Livebook.Runtime.ErlDist.NodeManager, {:orphan_log, message})
    end
  end
end
```

Registered in `lib/livebook/runtime/erl_dist/node_manager.ex` (lines 122-128):

```elixir
:logger.add_handler(:livebook_gl_handler, Livebook.Runtime.ErlDist.LoggerGLHandler, %{
  formatter: Logger.Formatter.new(),
  filters: [
    code_server_logs:
      {&Livebook.Runtime.ErlDist.LoggerGLHandler.filter_code_server_logs/2, nil}
  ]
})
```

Also includes a filter to suppress benign "Error loading module" messages during intellisense (`filter_code_server_logs/2`).

### 2.9 General Logging Patterns

Livebook uses `require Logger` and standard `Logger.info/warning/error/debug` throughout. Key patterns observed:

- **App-scoped logs**: `[app=#{slug}]` prefix (e.g., `apps/deployer.ex:90`)
- **File system logs**: `[file_system=#{name}]` prefix (e.g., `file_system/mounter.ex:99`)
- **K8s runtime logs**: `[k8s runtime]` prefix (e.g., `runtime/k8s.ex:156`)
- **Teams connection**: descriptive labels like "Teams WebSocket connection - established" (`teams/connection.ex:46`)

---

## 3. Tracing & APM

**No tracing or APM integration exists.** Livebook does not use:

- Sentry
- OpenTelemetry
- AppSignal
- W3C trace context
- Distributed tracing headers
- Custom span creation

The only "tracing-adjacent" feature is `Plug.Telemetry` for endpoint timing, consumed by LiveDashboard.

---

## 4. Metrics

### 4.1 Phoenix LiveDashboard

`lib/livebook_web/router.ex` (lines 170-177):

```elixir
scope "/" do
  pipe_through [:browser, :auth]

  live_dashboard "/dashboard",
    metrics: LivebookWeb.Telemetry,
    home_app: {"Livebook", :livebook},
    ecto_repos: []
end
```

Available at `/dashboard` (authenticated). The `metrics` callback points to `LivebookWeb.Telemetry.metrics/0` (see §1.2).

### 4.2 LiveDashboard Request Logger

`lib/livebook_web/endpoint.ex` (lines 60-62):

```elixir
plug Phoenix.LiveDashboard.RequestLogger,
  param_key: "request_logger",
  cookie_key: "request_logger"
```

Enables LiveDashboard's built-in request log streaming (accessible via cookie/param toggle).

### 4.3 SystemResources Process

`lib/livebook/system_resources.ex` — a GenServer that periodically measures system memory and broadcasts updates via PubSub (`{:memory_update, memory}`). Used for the in-UI resource display, not for metrics export.

### 4.4 No Prometheus / OpenMetrics

No `prometheus_ex`, `prometheus_phoenix`, or `telemetry_metrics_prometheus` dependency. No `/metrics` HTTP endpoint.

---

## 5. Health Checks

### 5.1 Health Endpoint

`lib/livebook_web/router.ex` (line 52):

```elixir
scope "/public", LivebookWeb do
  pipe_through :browser
  get "/health", HealthController, :index
end
```

`lib/livebook_web/controllers/health_controller.ex` (lines 1-11):

```elixir
defmodule LivebookWeb.HealthController do
  use LivebookWeb, :controller

  def index(conn, _params) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> json(%{
      "application" => "livebook"
    })
  end
end
```

- Returns `200 OK` with `{"application": "livebook"}`.
- Includes CORS header `access-control-allow-origin: *`.
- Lives under `/public/` namespace (no authentication required).
- **No dependency checks** — no database, no runtime status, no disk space check.

### 5.2 Health Check Consumer

`lib/livebook_cli/server.ex` (lines 126-135) — the CLI uses the health endpoint to probe availability before opening the browser:

```elixir
defp check_endpoint_availability(base_url) do
  Application.ensure_all_started(:req)
  health_url = set_path(base_url, "/public/health")
  req = Req.new() |> Livebook.Utils.req_attach_defaults()

  case Req.get(req, url: health_url, retry: false) do
    {:ok, %{status: 200, body: %{"application" => "livebook"}}} -> :livebook_running
    {:ok, _other} -> :taken
    {:error, _exception} -> :available
  end
end
```

---

## 6. Key Files Summary

| File | Role |
|---|---|
| `lib/livebook.ex` (lines 99-119) | Runtime logger config via env vars |
| `lib/livebook/config.ex` (lines 477-515) | Env var parsing for log level/format/metadata |
| `lib/livebook/application.ex` (line 9) | `Logger.add_handlers(:livebook)` |
| `lib/livebook_web/telemetry.ex` | Telemetry supervisor + metric definitions |
| `lib/livebook_web/endpoint.ex` (lines 60-65) | LiveDashboard RequestLogger, `Plug.RequestId`, `Plug.Telemetry` |
| `lib/livebook_web/router.ex` (lines 52, 170-177) | Health route, LiveDashboard mount |
| `lib/livebook_web/controllers/health_controller.ex` | Minimal health check handler |
| `lib/livebook/session.ex` (lines 2787-2820) | Structured code evaluation logging |
| `lib/livebook/utils.ex` (lines 976-990) | `logger_users_metadata/1` helper |
| `lib/livebook_web/plugs/user_plug.ex` (line 89) | `Logger.metadata` injection for users |
| `lib/livebook_web/live/hooks/user_hook.ex` (line 28) | `Logger.metadata` injection for users (LV) |
| `lib/livebook/runtime/erl_dist/logger_gl_handler.ex` | Custom GL handler for runtime node logs |
| `config/config.exs` (lines 12-15) | Default log format + metadata |
| `config/prod.exs` (line 15) | `:warning` default log level |
| `config/test.exs` (lines 21-29) | Test-time JSON logger setup |

---

## 7. Key Takeaways

1. **No APM / tracing** — Livebook has zero APM instrumentation. No Sentry, OpenTelemetry, or custom span creation.
2. **Environment-driven log configuration** — `LIVEBOOK_LOG_FORMAT=json` switches to `logger_json`; `LIVEBOOK_LOG_METADATA` controls which keys (users, code, session_mode, event) are attached.
3. **Audit logging via structured metadata** — Code evaluation emits structured logs with `event: "code.evaluate"`, user identity, and code content. JSON format is required for production audit use.
4. **Minimal telemetry** — Only Phoenix endpoint/router durations and VM metrics. No custom business metrics. Periodic measurements callback is stubbed out.
5. **Single health endpoint** — Returns `{"application": "livebook"}` with no dependency checks. No `/metrics` endpoint.
6. **LiveDashboard as the only metrics UI** — No Prometheus, no StatsD, no custom metrics export.
7. **Custom log handler for runtimes** — `LoggerGLHandler` forwards logs from evaluator (notebook execution) processes back to the main node.
