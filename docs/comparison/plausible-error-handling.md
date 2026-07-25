# Plausible Error Handling Patterns

> Explored 2026-07-25. Based on commit at `/tmp/comparison_repos/plausible`.

## 1. Custom Error Structs (No `defexception`)

Plausible does **not** use `defexception` anywhere. Instead it uses `defstruct`-based error structs that are returned as `{:error, %Struct{}}` tuples — never raised.

### `Plausible.Stats.QueryError`

`lib/plausible/stats/query_error.ex:1-4`:

```elixir
defmodule Plausible.Stats.QueryError do
  defstruct [:code, :message]
end
```

A plain struct with `:code` + `:message`. Used to carry validation/schema errors from the query parser layer up to controllers. It is pattern-matched in `with`/`else` blocks rather than raised.

### `Plausible.HTTPClient.Non200Error`

`lib/plausible/http_client.ex:1-13`:

```elixir
defmodule Plausible.HTTPClient.Non200Error do
  defstruct reason: nil

  def new(%Finch.Response{status: status} = response)
      when is_integer(status) and (status < 200 or status >= 300) do
    %__MODULE__{reason: response}
  end
end
```

A wrapper that converts non-2xx Finch responses into `{:error, %Non200Error{}}` tuples. The `tag_error/1` private function (line 118-129) converts `{:ok, %Finch.Response{status: s}}` to `{:error, Non200Error.new(response)}` when status is not in 200-299 range.

### Summary

| Pattern | Used? |
|---------|-------|
| `defexception` | ❌ Never |
| `defstruct` error carriers | ✅ `QueryError`, `Non200Error` |
| Raised exceptions in business logic | ❌ (only `raise` in `force_create_my_team` for programmer errors) |

---

## 2. Error Handling Patterns

### `with` Chains — The Dominant Pattern

The codebase uses `with` extensively (90+ matches in `lib/plausible/`). Every step returns either `:ok` / `{:ok, value}` or `{:error, reason}`. The `else` clause pattern-matches on specific error atoms/tuples.

**Canonical example —** `lib/plausible_web/controllers/api/stats_controller.ex:23-35`:

```elixir
with {:ok, %ParsedQueryParams{} = params} <- Dashboard.QueryParser.parse(params, now: now),
     {:ok, %Query{} = query} <- QueryBuilder.build(site, params, debug_metadata(conn)) do
  json(conn, Plausible.Stats.query(site, query))
else
  {:error, %QueryError{message: message}} -> H.bad_request(conn, message)
end
```

**Multi-error `else` —** `lib/plausible_web/controllers/api/stats_controller.ex:196-226`:

```elixir
with :ok <- Plausible.Billing.Feature.Funnels.check_availability(site.team),
     query <- Query.from(site, params, ...),
     :ok <- validate_funnel_query(query),
     {funnel_id, ""} <- Integer.parse(funnel_id),
     {:ok, funnel} <- Stats.funnel(site, query, funnel_id) do
  json(conn, funnel)
else
  {:error, {:invalid_funnel_query, due_to}} ->
    H.bad_request(conn, "We are unable to show funnels when the dashboard is filtered by #{due_to}")
  {:error, :funnel_not_found} ->
    conn |> put_status(404) |> json(%{error: "Funnel not found"}) |> halt()
  {:error, :upgrade_required} ->
    H.payment_required(conn, "...")
  _ ->
    H.bad_request(conn, "There was an error with your request")
end
```

### `case` Pattern Matching on OK/Error Tuples

Used when the logic doesn't fit `with` (e.g., needs to branch on more than error vs success, or mix with other conditions):

`lib/plausible_web/controllers/site_controller.ex:45-97`:

```elixir
case Sites.create(user, site_params, team) do
  {:ok, %{site: site}} -> redirect(...)
  {:error, _, :permission_denied, _} -> render("new.html", ...)
  {:error, _, {:over_limit, limit}, _} -> render("new.html", site_limit_exceeded: true, ...)
  {:error, _, changeset, _} -> ...
end
```

`lib/plausible_web/controllers/api/stats_controller.ex:270-297` (Google Search terms — mixed error + business logic):

```elixir
case {search_terms, period_too_recent?} do
  {{:error, :google_property_not_configured}, _} -> ...
  {{:error, :unsupported_filters}, _} -> ...
  {{:ok, []}, true} -> ...  # period too recent
  {{:ok, terms}, _} -> json(conn, %{results: terms})
  {{:error, error}, _} -> Logger.error(...); put_status(502) |> json(...)
end
```

### `try/rescue` — Rare, Kept for Infrastructure Code

`try/rescue` is mostly used in:
- **Cache adapter** (`lib/plausible/cache/adapter.ex`): Catches `:exit` signals from ConCache to prevent crashes on transient ETS failures
- **Oban error reporter** (`lib/oban_error_reporter.ex:9-15`): Wraps telemetry handler in try/catch to prevent handler detachment
- **Session transfer** (`lib/plausible/session/transfer/tinysock.ex`): Socket operations
- **Mailer** (`lib/plausible/mailer.ex:7`): Email sending errors

### `throw` / `catch`

Not used for control flow. Only `catch :exit` in `cache/adapter.ex` to handle ConCache ETS exits gracefully.

---

## 3. Error Translation (Controllers → HTTP Responses)

### No `action_fallback`

Plausible does **not** use Phoenix's `action_fallback` macro. Instead, errors are handled inline in each controller action via `with/else` and `case` pattern matching.

### `PlausibleWeb.Api.Helpers` — Error Response Helpers

`lib/plausible_web/controllers/api/helpers.ex:1-51`:

```elixir
def bad_request(conn, msg, extra \\ %{}) do
  payload = Map.merge(extra, %{error: msg})
  conn |> put_status(400) |> Phoenix.Controller.json(payload) |> halt()
end

def not_found(conn, msg), do: ...
def unauthorized(conn, msg), do: ...
def not_enough_permissions(conn, msg), do: ...  # 403
def too_many_requests(conn, msg), do: ...        # 429
def payment_required(conn, msg), do: ...          # 402
```

All follow the same pattern: `put_status` + `json(%{error: msg})` + `halt()`.

### `PlausibleWeb.ControllerHelpers` — HTML Error Rendering

`lib/plausible_web/controllers/helpers.ex:7-21`:

```elixir
def render_error(conn, status, message) do
  conn |> put_root_layout(false) |> put_status(status)
       |> put_view(PlausibleWeb.ErrorView) |> render("#{status}.html", ...)
end
```

### `PlausibleWeb.ErrorView` — Global Error View

`lib/plausible_web/views/error_view.ex:1-85`:

- `render("500.json", ...)` — distinguishes `plugins_api` via assigns for different JSON shape
- `render("404.html", ...)` — renders HTML with `PlausibleWeb.ErrorView`
- `template_not_found/2` — dynamic fallback for any status code; formats JSON as `%{status: s, message: m}` and HTML via `generic_error.html`
- Uses `Sentry.get_last_event_id_and_source()` to inject trace IDs into 5xx pages

### Plugins API — OpenAPI-Guided Errors

`lib/plausible_web/plugins/api/errors.ex:1-53`:

```elixir
def error(conn, status, messages) when is_list(messages) do
  response = Jason.encode!(%{
    errors: Enum.map(messages, fn
      message when is_binary(message) -> %{detail: message}
      %Ecto.Changeset{} = changeset ->
        changeset |> traverse_errors() |> Enum.map(fn {key, msg} -> %{detail: "#{key}: #{msg}"} end)
    end) |> List.flatten()
  })
  conn |> put_resp_content_type("application/json") |> send_resp(status, response) |> halt()
end
```

Each Plugins API controller uses `Errors.error(conn, 422, changeset)` or dedicated helpers like `payment_required(conn)`.

### `Plug.ErrorHandler` Macro

`lib/plausible_web/plugs/error_handler.ex:1-20`:

```elixir
defmacro __using__(_) do
  quote do
    use Plug.ErrorHandler
    @impl Plug.ErrorHandler
    def handle_errors(conn, %{kind: kind, reason: reason}) do
      json(conn, %{error: "internal server error"})
    end
  end
end
```

Used by 6 controllers (StatsController, ExternalStatsController, ExternalQueryApiController, Internal-Annotations, Internal-Segments). Provides a blanket "internal server error" JSON response for unhandled exceptions in those API controllers.

### HTTP Status Codes Used (Non-Exhaustive)

| Code | Usage |
|------|-------|
| 400 | Validation errors, bad requests (most common) |
| 401 | Unauthorized (`Helpers.unauthorized`) |
| 402 | Payment/upgrade required (`Helpers.payment_required`) |
| 403 | Forbidden / not enough permissions |
| 404 | Resource not found |
| 422 | Unprocessable entity (validation in Plugins API) |
| 429 | Rate limited |
| 502 | External API failure (Google Search Console) |

---

## 4. Result Types

### No Dry-Monads / Custom Monads

Plausible does **not** use `dry-monads` or any custom `Result` type. It relies entirely on Elixir conventions:

- `:ok` / `{:ok, value}` for success
- `{:error, reason}` / `{:error, atom}` / `{:error, struct}` for errors
- `:ok` / `{:error, ...}` for side-effect-only operations
- Function names that end with `!` (e.g., `Repo.get_by!`) raise on failure

### `QueryError` as Error Carrier

`Plausible.Stats.QueryError` acts as a typed error struct (like a monadic `Left` value) but it is never used with a `Result` wrapper — it's always embedded in `{:error, %QueryError{}}`.

### Business Logic Error Atoms

Common error atoms across the codebase:

| Atom | Context |
|------|---------|
| `:rate_limit` | Rate limiting |
| `:upgrade_required` | Billing/plan restrictions |
| `:permission_denied` | Authorization failures |
| `:user_not_found` | Auth lookups |
| `:wrong_password` | Login |
| `:funnel_not_found` | Funnel queries |
| `:active_subscription` | Team deletion guard |
| `:fetch_prices_failed` | Paddle API |
| `:rate_limit_exceeded` | GA4 API |
| `:server_failed` / `:socket_failed` | GA4 transport errors |

---

## 5. Logging of Errors

### Logger.error — 27 call sites

Patterns observed:

**Logging + Sentry via `crash_reason` metadata** (`lib/oban_error_reporter.ex:68-77`):

```elixir
Logger.error(
  "Background job (#{inspect(extra)}) failed:\n\n  " <> Exception.format(:error, meta.reason, meta.stacktrace),
  crash_reason: {meta.reason, meta.stacktrace},
  sentry: %{extra: extra}
)
```

**Logging + Sentry context** — `lib/plausible/google/ga4/http.ex:127-131`:

```elixir
Sentry.Context.set_extra_context(%{google_analytics4_response: body})
Logger.error("Google Analytics 4: Failed to find report in response. Reason: #{inspect(body)}")
```

**Direct Logger.error + string interpolation** — throughout the codebase for operational errors (health checks, webhook processing, cache failures).

### Sentry Integration

`lib/plausible/application.ex:360-369`:

```elixir
def setup_sentry() do
  LoggerBackends.add(Sentry.LoggerBackend)   # all Logger calls bubble to Sentry
  :telemetry.attach_many("oban-errors", ...)
end
```

Configuration (`config/runtime.exs:596-606`):
```elixir
config :sentry,
  dsn: sentry_dsn,
  client: Plausible.Sentry.Client,             # custom HTTP client via Finch
  send_max_attempts: 1,
  before_send: {Plausible.SentryFilter, :before_send}  # filter/group events
```

Key integration points:
1. **`Sentry.PlugCapture`** — used in `Endpoint` to capture all unhandled plug exceptions
2. **`Sentry.PlugContext`** — enriches exceptions with request context
3. **`Sentry.LoggerBackend`** — all `Logger.error/warning` calls automatically sent to Sentry
4. **`Sentry.Context`** — manually enriched in GA4, LiveViews, and ingestion code
5. **`Sentry.capture_message`** — explicitly called (~15+ sites) for non-exception events like business rule violations, external API failures
6. **`Sentry.get_last_event_id_and_source()`** — displayed on 5xx HTML error pages for user support

### `Plausible.SentryFilter` — Event Filtering & Fingerprinting

`lib/sentry_filter.ex:1-69`:

Filters out known noise:
- `Bamboo.PostmarkAdapter.Error` (hard bounces → filtered)
- `Phoenix.NotAcceptableError`, `Plug.CSRFProtection`, `Plug.Static.InvalidPathError`
- Ranch listener process errors, Mint connection-closed messages

Groups similar errors by fingerprint:
- `DBConnection.ConnectionError` → fingerprint `["db_connection", reason]`
- `Mint.TransportError` / `Finch.TransportError` → fingerprint `["mint_transport", reason]`
- Ingestion requests → fingerprint `["ingestion_request"]`

### Custom Error Reporter for Oban Jobs

`lib/oban_error_reporter.ex:1-78`:

Telemetry-based handler attached in `setup_sentry/0`. On job failure:
1. Captures exception + stacktrace from telemetry metadata
2. If the job is on `analytics_imports` queue and has exhausted retries → marks the import as failed in DB
3. If transient → marks as transient failure
4. Always logs error with `crash_reason` metadata so Sentry picks it up

---

## 6. Validation

### Ecto Changeset Validations

Standard Ecto changeset validations throughout schemas. Example — `lib/plausible_web/plugins/api/errors.ex:38-43`:

```elixir
%Ecto.Changeset{} = changeset ->
  changeset
  |> traverse_errors()
  |> Enum.map(fn {key, message} -> %{detail: "#{key}: #{message}"} end)
```

Helper module — `lib/plausible/helpers/changeset.ex:1-34`:

```elixir
def traverse_errors(changeset) do
  Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
    Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end)
end

def serialize_first_error(errors) do
  {field, {message, opts}} = List.first(errors)
  formatted_message = Enum.reduce(opts, message, fn {key, value}, acc ->
    String.replace(acc, "%{#{key}}", to_string(value))
  end)
  "#{field} #{formatted_message}"
end
```

### JSON Schema Validation

`lib/plausible/stats/json_schema.ex:30-38`:

```elixir
def validate(params) do
  case ExJsonSchema.Validator.validate(@query_schema, params) do
    :ok -> :ok
    {:error, errors} ->
      {:error, %QueryError{code: :failed_schema_validation, message: format_errors(errors, params)}}
  end
end
```

The Stats API v2 uses JSON Schema (defined in `priv/json-schemas/query-api-schema.json`) as a first line of defense. Schema validation errors are converted to `QueryError` structs and returned as 400 responses.

### OpenAPI Validation (Plugins API)

`lib/plausible_web.ex:119`:

```elixir
plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true, replace_params: false)
```

Plugins API controllers use OpenApiSpex to cast and validate request bodies against OpenAPI schemas automatically. Validation errors render as 422 responses with the standard `%{errors: [...]}` shape.

### Rate Limiting as Validation

`lib/plausible/auth/auth.ex:106-113`:

```elixir
def rate_limit(limit_type, key) do
  %{prefix: prefix, limit: limit, interval: interval} = @rate_limits[limit_type]
  full_key = "#{prefix}:#{rate_limit_key(key)}"
  case RateLimit.check_rate(full_key, interval, limit) do
    {:allow, _} -> :ok
    {:deny, _} -> {:error, {:rate_limit, limit_type}}
  end
end
```

Rate limiting uses `:ok` / `{:error, ...}` tuples and integrates into `with` chains.

---

## 7. Key Architectural Differences vs. Typical Phoenix Practices

| Aspect | Plausible | Typical Phoenix |
|--------|-----------|-----------------|
| **`action_fallback`** | Not used — inline `with/else` in every action | Recommended by guides; centralizes error→HTTP translation |
| **Custom exceptions** | No `defexception` — uses `defstruct` + `{:error, %{}}` tuples | Common to define `defexception` for domain errors |
| **Error responses** | Ad-hoc via `Helpers` module, different JSON shapes (`error` vs `errors`) | Consistent via `ErrorView` + `action_fallback` |
| **Plug.ErrorHandler** | Custom macro wrapper adding Sentry + uniform JSON | Direct `use Plug.ErrorHandler` per controller |
| **Result types** | Pure Elixir tuples — no dry-monads | Some projects use `with_tagged/1` or similar |
| **Changeset errors** | Converted to `errors: [%{detail: ...}]` in Plugins API, `%{error: msg}` elsewhere | Usually rendered via Phoenix's `render_errors` |
| **JSON shape** | Inconsistent: `%{error: msg}` (helpers) vs `%{errors: [%{detail: ...}]}` (Plugins API) | Usually standardized per API version |
| **`on_ee` / `on_ce`** | Error handling branches for Enterprise vs Community Edition | Not a typical pattern |
| **Logger → Sentry** | `Sentry.LoggerBackend` captures ALL log messages | Usually only explicit `Sentry.capture_*` calls |

### Interesting Patterns Worth Noting

1. **Sentry trace ID on 5xx pages** — `ErrorView.render/2` calls `Sentry.get_last_event_id_and_source()` and renders it directly on server error HTML pages so users can reference it in support requests.

2. **Cache adapter's `catch :exit`** — All ConCache operations in `lib/plausible/cache/adapter.ex` are wrapped in `catch :exit` and log errors rather than crash. This is a defensive pattern for an infrastructure layer that should never bring down the application.

3. **Oban error reporter's `try/catch` on telemetry** — Prevents the telemetry handler from being detached if the handler itself crashes (per telemetry library recommendation).

4. **Dual API JSON shapes** — Internal stats API returns `%{error: msg}`, external plugins API returns `%{errors: [%{detail: ...}]}` (JSON:API-style). This suggests two different development eras or API design philosophies in the same codebase.

5. **`raise` used only for programmer errors** — `raise` appears only in `force_create_my_team` ("SSO user tried to force create a personal team") and `parse_passthrough!` ("Invalid passthrough"). Both are truly exceptional conditions that should never happen in production.
