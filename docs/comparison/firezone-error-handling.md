# Firezone Elixir: Error Handling Patterns

> Based on codebase at `/tmp/comparison_repos/firezone/elixir/` — a production Elixir/Phoenix app for zero-trust network access.

---

## 1. Custom Error Structs (`defexception`)

Six `defexception` definitions across the codebase, falling into three categories:

### 1.1 HTTP-facing errors (LiveView controllers)

**File:** `lib/portal_web/live_errors.ex` (lines 1–21)

```elixir
defmodule NotFoundError do
  defexception message: "Not Found", skip_sentry: false

  defimpl Plug.Exception do
    def status(_exception), do: 404
    def actions(_exception), do: []
  end
end

defmodule InvalidParamsError do
  defexception message: "Unprocessable Content"

  defimpl Plug.Exception do
    def status(_exception), do: 422
    def actions(_exception), do: []
  end
end
```

Key detail: `skip_sentry: false` is a field on `NotFoundError` — the `Plug.Exception` protocol is implemented to map directly to HTTP status codes. The `skip_sentry` flag is checked by the Sentry `before_send` filter.

### 1.2 Directory Sync errors (Oban job context)

Three structurally identical modules:

| File | Module |
|------|--------|
| `lib/portal/okta/sync_error.ex` | `Portal.Okta.SyncError` |
| `lib/portal/entra/sync_error.ex` | `Portal.Entra.SyncError` |
| `lib/portal/google/sync_error.ex` | `Portal.Google.SyncError` |

Each declares:

```elixir
defexception [:message, :error, :directory_id, :step]
```

And customizes `exception/1` to build a rich human-readable message:

```elixir
def exception(opts) do
  error = Keyword.get(opts, :error)
  directory_id = Keyword.fetch!(opts, :directory_id)
  step = Keyword.fetch!(opts, :step)
  message = build_message(error, directory_id, step)
  %__MODULE__{message: message, error: error, directory_id: directory_id, step: step}
end
```

These carry **structured context** (`error`, `directory_id`, `step`) that is extracted by the Oban telemetry reporter and forwarded to Sentry.

### 1.3 SSRF Protection error

**File:** `lib/portal/req/ssrf_protection.ex` (lines 28–43)

```elixir
defmodule UnsafeURLError do
  defexception [:host, :reason]

  def message(%__MODULE__{host: host, reason: :non_public_address}) do
    "request to #{inspect(host)} was blocked because it resolves to a private or reserved IP address"
  end
  def message(%__MODULE__{host: host, reason: :nxdomain}) do
    "request to #{inspect(host)} failed because the host could not be resolved"
  end
  def message(%__MODULE__{host: host, reason: :invalid_url}) do
    "request was blocked because #{inspect(host)} is not a valid HTTP host"
  end
end
```

Pattern: **pattern-match on `:reason` in `message/1`** to produce tailored error messages — avoids large `case` statements.

---

## 2. HTTP Error Translation (Controllers)

### 2.1 Centralized Error Handlers (No `action_fallback`)

Firezone **explicitly prohibits** `action_fallback`. A custom Credo check enforces this:

**File:** `.credo/check/warning/action_fallback_usage.ex` (lines 7–11)

```elixir
check: """
The `action_fallback` macro should not be used in controllers.

Using `action_fallback` breaks stack traces and makes error handling
harder to follow. Instead, use explicit error handling with a
centralized Error module.
"""
```

Instead, every controller follows the **`with`/`else` → `Error.handle/2`** pattern:

```elixir
with {:ok, client} <- Database.fetch_client(id, subject),
     changeset = update_changeset(client, params),
     {:ok, client} <- Database.update_client(changeset, subject) do
  render(conn, :show, client: client)
else
  error -> Error.handle(conn, error)
end
```

79 call sites across all API controllers follow this pattern.

### 2.2 Web Controller Error Handler

**File:** `lib/portal_web/controllers/error.ex` (lines 1–46)

Pattern-matches on `{:error, atom}` tuples:

```elixir
def handle(conn, {:error, :not_found}) do
  conn |> put_status(:not_found) |> put_layout(html: {PortalWeb.Layouts, :root})
       |> put_view(PortalWeb.ErrorHTML) |> render("404.html")
end

def handle(conn, {:error, :unauthorized}) do
  conn |> put_status(:unauthorized) |> put_layout(html: {PortalWeb.Layouts, :root})
       |> put_view(PortalWeb.ErrorHTML) |> render("401.html")
end

def handle(conn, error) do
  Logger.error("Unhandled Web error", error: inspect(error))
  conn |> put_status(:internal_server_error) |> put_view(PortalWeb.ErrorHTML)
       |> render("500.html")
end
```

Catch-all clause logs and returns 500.

### 2.3 API Controller Error Handler (RFC 9457)

**File:** `lib/portal_api/controllers/error.ex` (lines 1–64)

Same pattern but richer — supports `{:error, atom, keyword}` tuples with reasons:

```elixir
def handle(conn, {:error, :bad_request}) do
  ProblemDetails.send(conn, 400, "The request could not be processed.")
end

def handle(conn, {:error, :bad_request, reason: reason}) do
  ProblemDetails.send(conn, 400, reason)
end

def handle(conn, {:error, :forbidden, reason: reason}) do
  ProblemDetails.send(conn, 403, reason)
end

def handle(conn, {:error, :conflict, reason: reason}) do
  ProblemDetails.send(conn, 409, reason)
end
```

Changeset errors get special treatment with RFC 9457 extension members:

```elixir
def handle(conn, {:error, %Ecto.Changeset{} = changeset}) do
  ProblemDetails.send(conn, 422, "The request body failed validation.", %{
    validation_errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
  })
end
```

### 2.4 ProblemDetails Module

**File:** `lib/portal_api/problem_details.ex` (lines 1–35)

Implements RFC 9457:

```elixir
def send(conn, status, detail, extensions \\ %{}) do
  body = %{
    type: "about:blank",
    title: Plug.Conn.Status.reason_phrase(status),
    status: status,
    detail: detail
  } |> Map.merge(extensions)

  conn |> put_resp_content_type("application/problem+json")
       |> Plug.Conn.send_resp(status, Phoenix.json_library().encode_to_iodata!(body))
       |> halt()
end
```

### 2.5 Error Views

- **Web HTML:** `lib/portal_web/controllers/error_html.ex` — uses `status_message_from_template/1` fallback
- **Custom heex pages:** `error_html/404.html.heex` (153 lines, styled with SVG/logo) and `error_html/500.html.heex` (183 lines, with pulse animation)
- **Web JSON:** `lib/portal_web/controllers/error_json.ex` — simple `%{errors: %{detail: "..."}}` map
- **API:** No `ErrorJSON` — API errors go through `ProblemDetails` directly from `Error.handle/2`

---

## 3. Error Handling Patterns (`with` / `try` / `rescue`)

### 3.1 `with` + `{:ok, _}` / `{:error, _}` (Dominant Pattern)

Used in virtually all controller actions (79 call sites) and many context modules. Example from `lib/portal_api/controllers/client_controller.ex`:

```elixir
def update(conn, %{"id" => id, "client" => params}) do
  subject = conn.assigns.subject
  with {:ok, client} <- Database.fetch_client(id, subject),
       changeset = update_changeset(client, params),
       {:ok, client} <- Database.update_client(changeset, subject) do
    render(conn, :show, client: client)
  else
    error -> Error.handle(conn, error)
  end
end
```

Pattern in context/domain modules:

```elixir
def use_token(encoded_token, %Context{} = context) do
  with {:ok, {nonce, account_id, id, fragment}} <- decode_token_with_context(encoded_token, context),
       {:ok, token} <- Database.fetch_token_for_use(account_id, id, context),
       :ok <- verify_secret_hash(token, nonce, fragment) do
    {:ok, token}
  else
    error ->
      Logger.info("Token use failed", error: error)
      {:error, :invalid_token}
  end
end
```

### 3.2 `try`/`rescue` (Defensive Boundaries)

47 `rescue` blocks found. Used sparingly, primarily at:

- **DB cast errors** (`Portal.Safe`, lines 701–731) — catches `Ecto.Query.CastError`, `Ecto.CastError`, `ArgumentError` and returns `nil` or reraises as `Ecto.NoResultsError`
- **Replica fallback** (`Portal.Safe`, lines 787–800) — catches `DBConnection.ConnectionError` and falls back to primary:
  ```elixir
  defp read_replica(fun, retry?) do
    safe_repo(fun)
  rescue
    error in DBConnection.ConnectionError ->
      if retry? do
        Logger.warning("Replica read failed, falling back to primary")
        :fallback
      else
        reraise error, __STACKTRACE__
      end
  end
  ```
- **Sentry context builder crash guard** (`lib/portal/telemetry/reporter/oban.ex`, line 34):
  ```elixir
  defp safe_handle_error(meta) do
    handle_error(meta)
  rescue
    exception ->
      Logger.error("Oban error handler crashed while building Sentry context",
        error: Exception.format(:error, exception, __STACKTRACE__))
      build_sentry_context(meta.job)
  end
  ```
- **External API calls** — Sentinal, Google sync, Entra API client
- **Cookie decoding** — several `rescue` in `PortalWeb.Cookie.*` modules
- **Domain encoding** (`Portal.Changeset`, line 239) — catches IDNA encoding failures

### 3.3 No Monads / Result Types

No `dry-monads`, `witch`, or custom result type libraries found. The codebase uses:
- `{:ok, value} | {:error, reason}` tuples (standard Elixir convention)
- `:ok` for side-effect-only success
- `nil` returns from `Safe.one/2` when a record is not found (then wrapped to `{:error, :not_found}` by controllers)

The `Portal.Safe` module uses a `Scoped`/`Unscoped` struct pattern (not a monad) to thread authorization context through database operations.

---

## 4. Sentry Integration

### 4.1 Configuration

**File:** `lib/portal/application.ex` (lines 86–108)

```elixir
# Attach Sentry logger handler at :warning level
:logger.add_handler(:sentry, Sentry.LoggerHandler, %{
  config: %{level: :warning, metadata: :all, capture_log_messages: true}
})
```

DSN configured via `sentry_dsn` env var (`lib/portal/config/definitions.ex`, line 765).

### 4.2 Sentry Event Filtering

**File:** `lib/portal/telemetry/sentry.ex` (lines 1–39)

Three categories of ignored events:

1. **Exceptions with `skip_sentry: true`** — the `NotFoundError` struct carries this flag for non-error 404s
2. **`Ecto.NoResultsError`** — expected under normal operation when resources aren't found
3. **`Plug.CSRFProtection.InvalidCSRFTokenError`** — from bots/scanners
4. **Libcluster and partition messages** — matched by regex on formatted message

```elixir
def before_send(%{original_exception: %{skip_sentry: skip_sentry}}) when skip_sentry do
  nil
end

def before_send(%{original_exception: %Ecto.NoResultsError{}}) do
  nil
end
```

### 4.3 Oban Job Errors → Sentry

**File:** `lib/portal/telemetry/reporter/oban.ex` (lines 1–57)

Attaches to `[:oban, :job, :exception]` telemetry events:

```elixir
def handle_event([:oban, :job, :exception], _measure, meta, _config) do
  sentry_context = safe_handle_error(meta)
  Sentry.capture_exception(meta.reason, stacktrace: meta.stacktrace, extra: sentry_context)
end
```

Routes to domain-specific handlers (Entra, Google, Okta) based on `meta.job.worker`. Each handler updates directory state and returns structured Sentry context.

### 4.4 Sentry Plug Context

Both Web and API endpoints include:

```elixir
plug Sentry.PlugContext
```

---

## 5. Validation Patterns

### 5.1 Custom Changeset Validators

**File:** `lib/portal/changeset.ex` (718 lines) — substantial custom validation module.

| Validator | Line | Purpose |
|-----------|------|---------|
| `validate_list/4` | 199 | Validates list elements with type-checking and index reporting |
| `validate_does_not_end_with/4` | 246 | Rejects values ending with a suffix |
| `validate_uri/3` | 257 | URI validation with scheme, trailing-slash, private-IP checks |
| `validate_public_host/2` | 299 | Blocks private/reserved IP addresses via DNS resolution |
| `validate_email/2` | 359 | Format + max length (160 chars) |
| `validate_one_of/3` | 388 | Tries multiple validators, succeeds if any passes |
| `validate_not_in_cidr/4` | 411 | Rejects IPs overlapping with a CIDR |
| `validate_and_normalize_cidr/3` | 432 | Cast+normalize CIDR, errors on invalid |
| `validate_and_normalize_ip/3` | 447 | Cast+normalize IP, errors on invalid |
| `validate_base64/2` | 460 | Base64 decode check |
| `validate_hash/4` | 472 | Verifies value matches stored hash |
| `validate_required_one_of/2` | 494 | At least one field must be present |
| `validate_datetime/3` | 509 | DateTime must be > reference |
| `validate_date/3` | 519 | Date must be > reference |
| `validate_fqdn/3` | 529 | FQDN with optional port validation |
| `validate_ip_type_inclusion/3` | 576 | Ensures IP is IPv4 or IPv6 |

These use `Ecto.Changeset.validate_change/3` internally, returning `[{field, message}]` tuples.

### 5.2 Polymorphic Embed Support

`cast_polymorphic_embed/3` (line 619) — replaces a map field with an embedded schema at runtime:

```elixir
def cast_polymorphic_embed(changeset, field, opts) do
  on_cast = Keyword.fetch!(opts, :with)
  # Temporarily swaps types to {:embed, %Ecto.Embedded{...}},
  # runs validation, then dumps back to :map
end
```

### 5.3 Config Validation

**File:** `lib/portal/config/validator.ex` (175 lines)

Uses `Ecto.Changeset` under the hood for runtime config validation. Supports `{:array, ...}`, `{:json_array, ...}`, `{:one_of, types}`, `{:embed, type}`, and custom `:changeset` callbacks:

```elixir
def validate(key, value, type, opts) do
  {%{}, %{key => type}}
  |> cast(%{key => value}, [key], empty_values: [])
  |> apply_validations(callback, type, key)
  # returns {:ok, value} | {:error, {value, errors}}
end
```

### 5.4 Feature-flag Validators (in Controllers)

Controllers add feature-check validators to changesets:

```elixir
# lib/portal_api/controllers/resource_controller.ex, lines 229–265
def validate_static_device_pool_feature_enabled(changeset, account) do
  if Ecto.Changeset.get_field(changeset, :type) == :static_device_pool and
     not client_to_client_enabled?(account) do
    Ecto.Changeset.add_error(changeset, :type, "device pools are not enabled for this account")
  else
    changeset
  end
end
```

### 5.5 Schema Changeset Validation

Standard Ecto schema validations with `changeset/2` functions. Example from `lib/portal/policies/condition.ex` (lines 49–119):

```elixir
def changeset(%__MODULE__{} = condition, attrs, _position) do
  condition
  |> cast(attrs, [:property, :operator, :values])
  |> validate_required([:property, :operator])
  |> validate_operator()
  |> validate_unique_values()
end
```

---

## 6. Logging

### 6.1 Logger Usage

Extensive Logger usage across the codebase — ~200+ call sites across production code:

| Level | Typical usage |
|-------|---------------|
| `Logger.error` | Unhandled errors, Oban crashes, billing failures, DB errors |
| `Logger.warning` | Replica fallback, network errors, rate limiting, unexpected API responses |
| `Logger.info` | Expected operational events: migrations, worker runs, sync completions, operational state changes |
| `Logger.debug` | Scheduled job start/stop, low-value operational noise |

Structured logging via `LoggerJSON` — configured at `lib/portal/application.ex` line 91:

```elixir
:ok = LoggerJSON.configure_log_level_from_env!("LOG_LEVEL")
```

Uses `LoggerJSON.Formatters.Basic` for JSON output.

### 6.2 Error Logging Patterns

**Controllers** — catch-all logs the error before returning 500:

```elixir
# lib/portal_api/controllers/error.ex, line 55
def handle(conn, error) do
  Logger.error("Unhandled API error", error: inspect(error))
  ProblemDetails.send(conn, 500, "An unexpected error occurred.")
end
```

**Oban** — crash-safe Sentry context building with error logging:

```elixir
# lib/portal/telemetry/reporter/oban.ex, line 36
Logger.error("Oban error handler crashed while building Sentry context",
  error: Exception.format(:error, exception, __STACKTRACE__))
```

**Replicas** — structured warning on fallback:

```elixir
# lib/portal/safe.ex, line 792
Logger.warning("Replica read failed, falling back to primary",
  error: Exception.message(error))
```

---

## 7. Key Differences from Typical Practices

| Aspect | Firezone | Typical Phoenix | Notes |
|--------|----------|-----------------|-------|
| **`action_fallback`** | **Banned** — custom Credo check prevents it | Commonly used | Reasoning: stack traces are clearer without it |
| **Error translation** | Explicit `Error.handle/2` with pattern matching | `action_fallback` + `fallback_controller` | More boilerplate but explicit |
| **Error tuples** | `{:error, atom}` and `{:error, atom, keyword}` | Usually just `{:error, atom}` | Extended tuples carry contextual reason |
| **RFC 9457** | Implemented from scratch in `ProblemDetails` | Often `jsonapi` or `phoenix` built-in | Lightweight, no dependency |
| **Changeset errors → API** | `traverse_errors` + custom `translate_error` | Often `Ecto.Changeset.traverse_errors` directly | Custom message interpolation |
| **Sentry** | Custom `before_send` filter; `skip_sentry` flag on exception struct | Typically just `Sentry.PlugContext` + config | Fine-grained control over noise |
| **Oban error handling** | Telemetry reporter routes to domain handlers | Often just `Sentry.capture_exception` in worker | Domain handlers update DB state + build context |
| **Result types** | Standard `{:ok, _}` / `{:error, _}` tuples | Some projects use `witch` or `dry-monads` | No monad library |
| **DB read errors** | `safe_repo` wrapper catches cast errors | Typically let errors propagate | Defensive boundary at the DB layer |
| **Replica fallback** | Catches `DBConnection.ConnectionError` and retries primary | Often no fallback or different mechanism | Explicit with `fallback_to_primary: true` option |
| **Credo checks** | Custom check for `action_fallback` | Vanilla Credo config | Enforced team convention |
| **Custom changeset validators** | 16+ custom `validate_*` functions | ~3–5 is typical | Heavy networking/IP validation needs |

---

## 8. Architecture Diagram (Error Flow)

```
Controller Action
      │
      ├── with {:ok, result} <- Domain.call()
      │                          │
      │                          ├── {:ok, value} ──► render(conn, :show, ...)
      │                          │
      │                          └── {:error, reason}
      │                                         │
      └── else error ───────────────────────────┘
                        │
                        ▼
              Error.handle(conn, error)
                        │
            ┌───────────┼───────────────┐
            │           │               │
            ▼           ▼               ▼
      {:error, atom}  {:error, atom,  %Ecto.Changeset{}
                       kw}
            │           │               │
            ▼           ▼               ▼
      Pattern match ──► ProblemDetails.send() / put_view()+render()
                        │
                        ├── 400 Bad Request
                        ├── 401 Unauthorized
                        ├── 403 Forbidden
                        ├── 404 Not Found
                        ├── 409 Conflict
                        ├── 422 Unprocessable Entity (changeset errors)
                        └── 500 Internal Server Error (catch-all, logged)

Concurrent Error Paths (Oban workers):

      Oban Job Failure
           │
           ▼
    [:oban, :job, :exception] telemetry
           │
           ▼
    Portal.Telemetry.Reporter.Oban.handle_event()
           │
           ├── safe_handle_error(meta)
           │        │
           │        ├── Directory sync? → Portal.DirectorySync.ErrorHandler
           │        │        │
           │        │        ├── Classify error (client_error / transient / internal)
           │        │        ├── Format user-friendly message
           │        │        └── Update directory state (disable after 24h of transient errors)
           │        │
           │        └── Other jobs → default context from job metadata
           │
           └── Sentry.capture_exception(reason, stacktrace, extra: sentry_context)
```

---

## 9. Summary

Firezone's error handling is characterized by:

1. **Explicitness over magic** — `action_fallback` banned by CI, all error branches explicit
2. **Structured error types** — sync errors carry `directory_id`, `step`, original error; HTTP errors carry reason keywords
3. **Defensive boundaries** — `rescue` at DB layer, replica fallback, Sentry context builder crash guard
4. **Layered reporting** — Logger (structured JSON) → Sentry (with fine-tuned filters) → OpenTelemetry
5. **Domain-aware Oban errors** — each directory provider has its own error classification, formatting, and state mutation logic
6. **No monads** — sticks to `{:ok, _} | {:error, _}` tuples throughout
