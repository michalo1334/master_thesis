# Logflare Error Handling Patterns

> Thorough analysis of `/tmp/comparison_repos/logflare` (commit TBD).

---

## Table of Contents

1. [Custom Error Structs / `defexception`](#1-custom-error-structs--defexception)
2. [Error Handling Patterns](#2-error-handling-patterns)
3. [Error Translation — Fallback Controller & HTTP Mapping](#3-error-translation--fallback-controller--http-mapping)
4. [OpenAPI Error Schemas](#4-openapi-error-schemas)
5. [Result Types](#5-result-types)
6. [Logging of Errors](#6-logging-of-errors)
7. [Validation — Changeset & Custom Validators](#7-validation--changeset--custom-validators)
8. [Exception Handling in Plugs / Parsers](#8-exception-handling-in-plugs--parsers)
9. [Summary Table](#9-summary-table)

---

## 1. Custom Error Structs / `defexception`

Logflare is minimalist with custom exceptions. Only **two** `defexception` definitions exist:

### a) `InvalidResourceError` — LiveView usage

**File:** `lib/logflare_web/live/errors_live.ex:2-4`

```elixir
defmodule LogflareWeb.ErrorsLive do
  defmodule InvalidResourceError do
    defexception message: "Resource not found", plug_status: 404
  end
end
```

Used inside LiveViews to abort rendering with a `Plug.Conn.status`-aware exception.

### b) `BadRequestError` — Custom JSON body parser

**File:** `lib/logflare_web/controllers/plugs/json_parser.ex:61-64`

```elixir
defmodule BadRequestError do
  defexception [:message, :plug_status]
end
```

Raised when the body reader returns an unexpected error (not timeout/not too large). Carries both a `:message` and `:plug_status` (always 400).

```elixir
# json_parser.ex:55-59
defp decode({:error, err}, _decoder, _opts) do
  raise __MODULE__.BadRequestError,
    message: "Body reader error: #{inspect(err)}",
    plug_status: 400
end
```

---

## 2. Error Handling Patterns

### 2a. `with` chains — the dominant pattern in API controllers

Every management API controller uses `with` chains that produce `{:ok, _}` / `{:error, _}` tuples, which fall through to `action_fallback`.

**Example — `SourceController.update/2`:**

**File:** `lib/logflare_web/controllers/api/source_controller.ex:82-96`

```elixir
def update(%{assigns: %{user: user}} = conn, %{"token" => token} = params) do
  with {:ok, source} <- Sources.fetch_source_by(token: token, user_id: user.id),
       {:ok, source} <- Sources.update_source_by_user(source, params) do
    source = Sources.preload_defaults(source)
    conn
    |> case do
      %{method: "PATCH"} -> conn |> send_resp(204, "")
      %{method: "PUT"}   -> conn |> put_status(200) |> json(source)
    end
  end
end
```

**Example — `QueryController.query/2` chain of 4 steps:**

**File:** `lib/logflare_web/controllers/api/query_controller.ex:123-131`

```elixir
def query(%{assigns: %{user: user}} = conn, params) do
  with {:ok, language, sql} <- extract_query(params),
       {:ok, backend} <- fetch_backend(user, params),
       language = resolve_language(language, backend),
       opts = build_query_opts(backend),
       {:ok, %{rows: rows}} <- Endpoints.run_query_string(user, {language, sql}, opts) do
    json(conn, %{result: rows})
  end
end
```

The bare assignment `language = ...` and `opts = ...` cannot fail, so they don't break the chain.

### 2b. `with` + `else` for explicit error handling (within context functions)

**File:** `lib/logflare/backends/adaptor/bigquery_adaptor.ex:735-744`

```elixir
defp to_query_error(%{body: body}, user_id) when is_binary(body) do
  with {:ok, %{"error" => raw_error}} <- Jason.decode(body),
       %{"message" => _message} = processed_error <-
         GenUtils.process_bq_errors(raw_error, user_id) do
    processed_error
    |> query_error_kind()
    |> query_error(processed_error)
  else
    _error -> query_error(:backend_error, body)
  end
end
```

### 2c. `try/rescue` for DB adaptor query execution

Adaptors catch known database exceptions and convert them to `%QueryError{}` structs.

**File:** `lib/logflare/backends/adaptor/postgres_adaptor.ex:92-106`

```elixir
def execute_query(%Backend{} = backend, %Ecto.Query{} = query, _opts) do
  mod = PgRepo.create_repo(backend)
  try do
    result = query |> mod.all() |> Enum.map(&nested_map_update/1)
    {:ok, QueryResult.new(result, pg_meta(result))}
  rescue
    error in [Postgrex.Error, DBConnection.ConnectionError, Ecto.QueryError] ->
      {:error, error |> to_query_error() |> log_query_error(backend)}
  end
end
```

**File:** `lib/logflare/backends/adaptor/bigquery_adaptor.ex:208-234` (pattern with multiple rescue clauses):

```elixir
def execute_query({project_id, dataset_id, user_id}, {sql_string, params}, opts) do
  # ... setup ...
  case Tesla.request(request_opts) do
    {:ok, %Tesla.Env{status: 200, body: body}} -> {:ok, decode(body)}
    {:ok, %Tesla.Env{status: status}} when status in 400..499 ->
      {:error, to_query_error(%{body: "HTTP #{status}"}, user_id)}
    {:ok, %Tesla.Env{body: body}} ->
      {:error, to_query_error(%{body: body}, user_id)}
    {:error, error} ->
      {:error, to_query_error(error, user_id)}
  end
end
```

### 2d. `try/rescue/reraise` for OTLP protobuf endpoints

**File:** `lib/logflare_web/controllers/log_controller.ex:261-272`

```elixir
def otel_traces(%{assigns: %{source: source}} = conn, %ExportTraceServiceRequest{} = req) do
  req.resource_spans
  |> Processor.ingest(Logs.OtelTrace, source)
  |> protobuf_response(conn, %ExportTraceServiceResponse{})
rescue
  exception ->
    send_proto_error(conn, 500, "Internal server error")
    reraise exception, __STACKTRACE__
end
```

Sends a protobuf-encoded error response, then **re-raises** so the error is visible to the logger/runtime. Same pattern for `otel_metrics` and `otel_logs`.

### 2e. Pattern matching on `handle/2` in `LogController`

**File:** `lib/logflare_web/controllers/log_controller.ex:242-250`

```elixir
defp handle({:ok, _}, conn), do: render(conn, "index.json", message: @message)
defp handle(:ok, conn),      do: render(conn, "index.json", message: @message)

defp handle({:error, errors}, conn) do
  conn
  |> put_status(406)
  |> put_view(LogflareWeb.LogView)
  |> render("index.json", message: errors)
end
```

---

## 3. Error Translation — Fallback Controller & HTTP Mapping

### 3a. The central `FallbackController`

**File:** `lib/logflare_web/controllers/api/fallback_controller.ex` (72 lines)

This single module maps **every `{:error, ...}` tuple from a `with` chain** to an HTTP response. Used by 12 API controllers via `action_fallback(LogflareWeb.Api.FallbackController)`.

```elixir
defmodule LogflareWeb.Api.FallbackController do
  use Phoenix.Controller

  # Ecto changeset → 422
  def call(conn, {:error, %Changeset{} = changeset}) do
    errors = Changeset.traverse_errors(changeset, fn _, _, {message, _} -> message end)
    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})
  end

  # Auth failures → 401
  def call(conn, {:error, :unauthorized}) do
    conn |> put_status(401) |> json(%{error: "Unauthorized"}) |> halt()
  end

  # Buffer/rate limits → 429 with retry-after
  def call(conn, {:error, :buffer_full}) do
    conn |> put_status(429) |> put_resp_header("retry-after", "3")
         |> json(%{error: "Buffer Full: Too Many Requests"}) |> halt()
  end

  def call(conn, {:error, :too_many_requests}) do
    conn |> put_status(429) |> json(%{error: "Too Many Requests"}) |> halt()
  end

  def call(conn, {:error, :too_many_requests, message}) when is_binary(message) do
    conn |> put_status(429) |> json(%{error: message}) |> halt()
  end

  # Not found → 404
  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> json(%{error: "Not Found"})
  end

  # QueryError (struct) → 400 with generic user message
  def call(conn, {:error, %QueryError{}}) do
    conn |> put_status(400) |> json(%{error: QueryErrorHelpers.generic_query_error_message()})
  end

  # Map error → 400 (serializes the map as JSON)
  def call(conn, {:error, %{} = err_map}) do
    conn |> put_status(400) |> json(%{error: err_map})
  end

  # Atom error → converted to string → 400
  def call(conn, {:error, msg}) when is_atom(msg) do
    call(conn, {:error, Atom.to_string(msg)})
  end

  # String error → 400
  def call(conn, {:error, msg}) when is_binary(msg) do
    conn |> put_status(400) |> json(%{error: msg})
  end
end
```

**Dispatch priority** (top-to-bottom):

| Pattern | HTTP Status | Response Body |
|---------|-------------|---------------|
| `%Changeset{}` | 422 | `{"errors": {...}}` |
| `:unauthorized` | 401 | `{"error": "Unauthorized"}` |
| `:buffer_full` | 429 + `retry-after: 3` | `{"error": "Buffer Full: Too Many Requests"}` |
| `:too_many_requests` | 429 | `{"error": "Too Many Requests"}` |
| `{:too_many_requests, msg}` | 429 | `{"error": <msg>}` |
| `:not_found` | 404 | `{"error": "Not Found"}` |
| `%QueryError{}` | 400 | Generic backend error message |
| `%{}` map | 400 | `{"error": <map>}` |
| atom | 400 | atom → string |
| binary | 400 | `{"error": <string>}` |

### 3b. Plug-level error translation — `RateLimiter` and `BufferLimiter`

These plugs call `FallbackController.call/2` **directly** (not via `action_fallback`), short-circuiting the request pipeline.

**File:** `lib/logflare_web/controllers/plugs/rate_limiter.ex:37`

```elixir
|> FallbackController.call({:error, :too_many_requests, message})
```

**File:** `lib/logflare_web/controllers/plugs/buffer_limiter.ex:35`

```elixir
FallbackController.call(conn, {:error, :buffer_full})
```

### 3c. Endpoint query errors — direct rendering (no fallback)

**File:** `lib/logflare_web/controllers/endpoints_controller.ex:83-98`

The `EndpointsController` does **not** rely on the fallback controller for query errors. Instead it uses a `case` statement and renders user-friendly messages:

```elixir
case Endpoints.run_cached_query(...) do
  {:ok, result} ->
    render(conn, "query.json", result: result.rows)

  {:error, error = %QueryError{}} ->
    render(conn, "query.json",
      error: QueryErrorHelpers.query_error_message(error))

  {:error, _errors} ->
    render(conn, "query.json",
      error: QueryErrorHelpers.generic_query_error_message())
end
```

### 3d. `ErrorView` — HTML error pages (browser only)

**File:** `lib/logflare_web/views/error_view.ex:1-31`

```elixir
defmodule LogflareWeb.ErrorView do
  use LogflareWeb, :view

  def render("401.html", assigns), do: render("401_page.html", assigns)
  def render("403.html", assigns), do: render("403_page.html", assigns)
  def render("404.html", assigns), do: render("404_page.html", assigns)
  def render("500.html", assigns), do: render("500_page.html", assigns)

  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
```

All API errors are handled by `FallbackController`, so `ErrorView` only serves HTML browser pages. There's also an error container layout template at `lib/logflare_web/templates/error/error_container.html.eex`.

---

## 4. OpenAPI Error Schemas

**File:** `lib/logflare_web/open_api.ex:56-125`

Logflare defines named OpenAPI response schemas for each error category:

```elixir
defmodule NotFound do
  def schema do
    %Schema{
      title: "NotFoundResponse", type: :object,
      properties: %{error: %Schema{type: :string}}, required: [:error]
    }
  end
  def response, do: {"Not found", "application/json", schema()}
end

defmodule UnprocessableEntity do
  # ...  %{errors: %Schema{type: :object}}
end

defmodule BadRequest do
  # ... error is oneOf [string, object]
end

defmodule Unauthorized do
  # ... %{error: %Schema{type: :string}}
end

defmodule ServerError do
  # ... %{error: %Schema{type: :string}}
end
```

These are used in controller `operation` specs for OpenAPI documentation.

---

## 5. Result Types

### 5a. `QueryError` struct (the only custom result type)

**File:** `lib/logflare/backends/query_error.ex:1-37`

```elixir
defmodule Logflare.Backends.QueryError do
  @enforce_keys [:kind, :raw_error, :backend]
  defstruct [:kind, :raw_error, :backend, :description]

  @type kind :: :invalid_query | :connection_error | :backend_error
  @type t :: %__MODULE__{
    kind: kind(),
    raw_error: term(),
    backend: module(),
    description: String.t() | nil
  }
```

Has a `log/2` function that conditionally logs (suppresses logging for `:invalid_query`, logs as error for others):

```elixir
def log(%__MODULE__{kind: :invalid_query} = error, metadata) when is_list(metadata) do
  error  # no-op for invalid queries (user error, not system)
end

def log(%__MODULE__{} = error, metadata) when is_list(metadata) do
  Logger.error("Backend query error",
    metadata ++ [backend: inspect(error.backend), error_kind: error.kind,
                 error_string: inspect(error.raw_error)])
  error
end
```

### 5b. No dry-monads, no `with_tag`

Logflare does **not** use `dry-monads`, `ok_tuple`, or any result type library. Only standard Elixir `{:ok, _} / {:error, _}` tuples.

### 5c. `{:error, :not_found}` convention

Multiple context modules follow the same pattern:

| Module | File | Line |
|--------|------|------|
| `Sources.fetch_source_by/1` | `lib/logflare/sources.ex` | 185-192 |
| `Backends.fetch_backend_by/1` | `lib/logflare/backends.ex` | 524-535 |
| `KeyValues.fetch_key_value_by/1` | `lib/logflare/key_values.ex` | 40-43 |
| `Alerting.fetch_alert_query/1` | `lib/logflare/alerting.ex` | 110-117 |
| `Teams.fetch_team_by/1` | `lib/logflare/teams.ex` | 33-39 |
| `Partners.fetch_user_by_uuid/2` | `lib/logflare/partners.ex` | 75-80 |

```elixir
# sources.ex:185-192
def fetch_source_by(kw) do
  source = get_by(kw)
  if source, do: {:ok, source}, else: {:error, :not_found}
end
```

Also used in storage backends (S3, GCS) translating provider 404s:

```elixir
# s3.ex:22
{:error, {:http_error, 404, _}} -> {:error, :not_found}

# gcs.ex:48
{:error, %Tesla.Env{status: 404}} -> {:error, :not_found}
```

---

## 6. Logging of Errors

### 6a. Structured logging with `logger_json`

**File:** `mix.exs:201`

```elixir
{:logger_json, "~> 5.1"},
```

All `Logger` calls produce JSON-structured logs.

### 6b. `Logger.error` usage density

~100+ `Logger.error` / `Logger.warning` calls across the codebase. Key locations:

| Area | Example |
|------|---------|
| Backend query errors | `lib/logflare/backends/query_error.ex:25` — `Logger.error("Backend query error", ...)` |
| Stripe webhooks | `lib/logflare_web/stripe_webhook_handler.ex:152` — `Logger.error("Stripe webhook error", ...)` |
| ClickHouse adaptor | `lib/logflare/backends/adaptor/clickhouse_adaptor.ex` — connection & query errors |
| BigQuery adaptor init | `lib/logflare/google/bigquery/bigquery.ex:40-59` — dataset/table init errors |
| Cluster connection | `lib/logflare/cluster/postgres_strategy.ex:68` — `Logger.error(state.topology, "Failed to connect...")` |
| Buffer producer | `lib/logflare/backends/buffer_producer.ex:265-282` — discarded events, warnings |
| Dynamic pipeline | `lib/logflare/backends/dynamic_pipeline.ex:90,199` — pipeline start failures |
| System cache warmer | `lib/logflare/system_cache/warmer.ex:13` — `Logger.warning("SystemCache warmer failed")` |

### 6c. Telemetry events for operational errors

**File:** `lib/telemetry.ex` — Custom metrics for:

- `[:logflare, :ingest, :requests, :buffer_full]` — emitted by `BufferLimiter`
- `[:logflare, :rate_limiter]` — emitted by `RateLimiter`
- `[:logflare, :system, :top_processes, ...]` — system metrics
- `[:cachex, metric]` — cache metrics

### 6d. No external error tracking (Sentry/Honeybadger)

The mix.exs has **no** `sentry` or `honeybadger` or `appsignal` dependency. The "Sentry" in the codebase is purely an **output backend** (sending logs **to** Sentry as a datasink), not error monitoring.

Observability is instead done via:
- OpenTelemetry (`:opentelemetry`, `:opentelemetry_exporter`)
- Structured JSON logging (`:logger_json`)
- Custom `:telemetry` events
- `logflare_logger_backend` (pipes Logflare's own logs into itself)

### 6e. Selective error suppression

The `QueryError.log/2` function explicitly skips logging `:invalid_query` errors — these are user errors (bad SQL) and not actionable by ops.

---

## 7. Validation — Changeset & Custom Validators

### 7a. Backend config validation (per adaptor)

Every adaptor implements `validate_config/1` that returns an `Ecto.Changeset`:

| Adaptor | File | Line |
|---------|------|------|
| BigQuery | `lib/logflare/backends/adaptor/bigquery_adaptor.ex` | 262 |
| ClickHouse | `lib/logflare/backends/adaptor/clickhouse_adaptor.ex` | 172 |
| Postgres | `lib/logflare/backends/adaptor/postgres_adaptor.ex` | 211 |
| Webhook | `lib/logflare/backends/adaptor/webhook_adaptor.ex` | 99 |
| S3 | `lib/logflare/backends/adaptor/s3_adaptor.ex` | 72 |
| Sentry | `lib/logflare/backends/adaptor/sentry_adaptor.ex` | 50 |
| Datadog | `lib/logflare/backends/adaptor/datadog_adaptor.ex` | 61 |
| Elastic | `lib/logflare/backends/adaptor/elastic_adaptor.ex` | 76 |
| Loki | `lib/logflare/backends/adaptor/loki_adaptor.ex` | 102 |
| Syslog | `lib/logflare/backends/adaptor/syslog_adaptor.ex` | 80 |
| OTLP | `lib/logflare/backends/adaptor/otlp_adaptor.ex` | 57 |
| Axiom | `lib/logflare/backends/adaptor/axiom_adaptor.ex` | 51 |
| Incident.io | `lib/logflare/backends/adaptor/incidentio_adaptor.ex` | 95 |
| Last9 | `lib/logflare/backends/adaptor/last9_adaptor.ex` | 54 |

Example — BigQuery:

```elixir
# bigquery_adaptor.ex:262-270
def validate_config(changeset) do
  changeset
  |> Changeset.validate_format(:dataset_id, @bq_identifier_pattern,
       message: "must contain only letters, numbers, and underscores")
  |> Changeset.validate_format(:project_id, @gcp_project_id_pattern,
       message: "must be a valid GCP project ID")
end
```

### 7b. Source-level validators

**File:** `lib/logflare/sources/source.ex:323`

```elixir
def validate_source_ttl(changeset, source)
```

**File:** `lib/logflare/logs/validators/bq_schema_change_validator.ex:26-28`

```elixir
def validate(%LE{body: _body}, %Source{validate_schema: false}), do: :ok
def validate(%LE{body: body}, %Source{} = source) do
  # ... validates each log event body against the BigQuery schema ...
end
```

### 7c. LQL validation

**File:** `lib/logflare/lql/validator.ex:23`

```elixir
def validate(lql_rules, opts \\ []) when is_list(opts) do
```

### 7d. Endpoint query validation

**File:** `lib/logflare/endpoints/endpoint_query.ex:155`

```elixir
def validate_query(changeset, field) when is_atom_value(field) do
```

### 7e. User-level validators

**File:** `lib/logflare/user.ex:248-284`

```elixir
def validate_gcp_project(changeset, field, options \\ []) do ...
def validate_bq_dataset_id(changeset) do ...
def validate_bq_dataset_location(changeset) do ...
```

### 7f. LQL transformation data validators

Each SQL dialect transformer validates its input data:

| Module | File | Line |
|--------|------|------|
| BigQuery | `lib/logflare/lql/backend_transformer/bigquery.ex` | 46 |
| ClickHouse | `lib/logflare/lql/backend_transformer/clickhouse.ex` | 47 |
| Postgres | `lib/logflare/lql/backend_transformer/postgres.ex` | 44 |
| SQL dialect | `lib/logflare/sql/dialect_transformer/bigquery.ex` | 43 |

---

## 8. Exception Handling in Plugs / Parsers

### 8a. Custom JSON parser

**File:** `lib/logflare_web/controllers/plugs/json_parser.ex`

Overrides the standard `Plug.Parsers.JSON` to:
- Catch decode errors and raise `Plug.Parsers.ParseError` (line 36)
- Raise custom `BadRequestError` for body reader errors (line 56-59)

### 8b. Other parsers

All custom parsers follow similar `try/rescue` patterns:

- `bert_parser.ex:30` — rescues `MatchError` on invalid BERT
- `ndjson_parser.ex:51` — rescues parse errors per line
- `syslog_parser.ex:58` — rescues RFC 3164 parse failures
- `protobuf_parser.ex:39-48` — rescues protobuf decode failures

---

## 9. Summary Table

| Pattern | Where | Mechanism |
|---------|-------|-----------|
| **`with` chains** | All API controllers | `{:ok, _} / {:error, _}` → `action_fallback` |
| **Central fallback controller** | `FallbackController` | Pattern matches error tuple → HTTP status + JSON body |
| **Query error struct** | `Logflare.Backends.QueryError` | 3 kinds: `:invalid_query`, `:connection_error`, `:backend_error` |
| **DB → QueryError translation** | Each adaptor's `to_query_error/1` | Rescues DB exceptions, classifies by error code/message |
| **User-friendly query messages** | `QueryErrorHelpers` | Extracts missing field names per backend type |
| **Plug-level short-circuit** | `RateLimiter`, `BufferLimiter` | Calls `FallbackController.call/2` directly |
| **`try/rescue/reraise`** | OTLP endpoints in `LogController` | Sends error response, re-raises for visibility |
| **No Sentry/Honeybadger** | — | OpenTelemetry + structured JSON logging instead |
| **`Logger.error` selectively suppressed** | `QueryError.log/2` | `:invalid_query` is not logged (user error) |
| **No dry-monads** | — | Standard `{:ok, _} / {:error, _}` tuples only |
| **`{:error, :not_found}` conventions** | 6+ context modules | Consistent pattern for resource lookup |
| **OpenAPI error schemas** | `OpenApi.NotFound`, `.BadRequest`, etc. | Documented response shapes for API spec |
| **Per-adaptor config validation** | 14 adaptors | `validate_config/1` returns changeset |
| **Telemetry events** | Buffer full, rate limiting, system metrics | `:telemetry.execute/3` calls |
