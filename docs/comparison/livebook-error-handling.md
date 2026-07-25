# Livebook Error Handling Patterns

> Explored at commit `HEAD` of `/tmp/comparison_repos/livebook`.

## 1. Custom Error Structs (`defexception`)

Livebook defines **5 custom exceptions** — minimal, focused on HTTP boundary translation.

### File: `lib/livebook_web/errors.ex`
```elixir
# Lines 1-7
defmodule LivebookWeb.NotFoundError do
  defexception [:message, plug_status: 404]
end

defmodule LivebookWeb.BadRequestError do
  defexception [:message, plug_status: 400]
end
```

These two are the **primary HTTP-level exceptions**. They carry `plug_status` so Phoenix's error pipeline picks them up automatically. Used in the ProxyPlug to abort requests with 404/400.

### File: `lib/livebook/notebook/learn.ex` (lines 2-8)
```elixir
defmodule NotFoundError do
  defexception [:slug, plug_status: 404]
  def message(%{slug: slug}) do
    "could not find an example notebook matching #{inspect(slug)}"
  end
end
```
A **namespaced error** nested inside `Livebook.Notebook.Learn`. Custom `message/1` for user-friendly text.

### File: `lib/livebook/storage.ex` (lines 22-28)
```elixir
defmodule NotFoundError do
  defexception [:id, :namespace, plug_status: 404]
  def message(%{namespace: namespace, id: id}) do
    "could not find entry in \"#{namespace}\" with ID #{inspect(id)}"
  end
end
```
Nested inside `Livebook.Storage`. Includes `plug_status: 404` — these errors can **propagate to HTTP** if unhandled.

### File: `lib/livebook_cli/error.ex` (lines 1-3)
```elixir
defmodule LivebookCLI.Error do
  defexception [:message]
end
```
CLI-only error. No `plug_status` — it is never rendered via HTTP.

### Key insight
- Exceptions are **defined close to their usage domain** (namespaced, not all in one file).
- Most carry `plug_status` for **automatic HTTP status mapping** — Phoenix's `render_errors` pipeline picks them up.
- No custom `Plug.Exception` implementation needed; `plug_status` field is sufficient.

---

## 2. Tuples as Results (`{:ok, _}` / `{:error, _}`)

The **dominant pattern** across the codebase. Livebook does **not** use dry-monads or any custom result type.

### Service-layer functions return tagged tuples

**`lib/livebook/users.ex` (line 18):**
```elixir
@spec update_user(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
```

**`lib/livebook/notebook/app_settings.ex` (line 74):**
```elixir
@spec update(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
```

**`lib/livebook/sessions.ex` (lines 14, 41):**
```elixir
@spec create_session(keyword()) :: {:ok, Session.t()} | {:error, any()}
@spec fetch_session(id()) :: {:ok, Session.t()} | {:error, :not_found | :different_boot_id}
```

**`lib/livebook/session.ex` (line 858):**
```elixir
@spec fetch_file_entry_path(pid(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
```

### Callers use `with` / `case` to chain

**`lib/livebook/session.ex` (lines 981-1013):**
```elixir
defp init_state(id, worker_pid, opts) do
  with {:ok, data} <- init_data(opts) do
    # build state...
    {:ok, state}
  end
end

defp init_data(opts) do
  # ...
  if file do
    case Session.FileGuard.lock(file, self()) do
      :ok -> {:ok, %{data | file: file}}
      {:error, :already_in_use} -> {:error, "the given file is already in use"}
    end
  else
    {:ok, data}
  end
end
```

**`lib/livebook/k8s/pod.ex` (lines 124-129):**
```elixir
def validate_pod_template(%{"apiVersion" => "v1", "kind" => "Pod"} = pod, namespace) do
  with :ok <- validate_basics(pod),
       :ok <- validate_main_container(pod),
       :ok <- validate_namespace(pod, namespace) do
    validate_container_image(pod)
  end
end
```

### Internal helpers use `:error` atom (no tuple)

**`lib/livebook/session/data.ex` (lines 2382-2390):**
```elixir
defp fetch_cell_bin_entry(data, cell_id) do
  Enum.find_value(data.bin_entries, :error, fn entry ->
    entry.cell.id == cell_id && {:ok, entry}
  end)
end

defp fetch_file_entry(notebook, name) do
  Enum.find_value(notebook.file_entries, :error, fn file_entry ->
    file_entry.name == name && {:ok, file_entry}
  end)
end
```

---

## 3. `with` Statements — Chaining Without Else

`with` is used extensively for **sequential validation/operations**, but rarely with an `else` block. Instead, a single `case` or nested `with` at the top level destructures the result.

**`lib/livebook/k8s/pod.ex` (lines 124-129):**
```elixir
with :ok <- validate_basics(pod),
     :ok <- validate_main_container(pod),
     :ok <- validate_namespace(pod, namespace) do
  validate_container_image(pod)
end
```

**`lib/livebook/session/data.ex` (lines 1098-1103):**
```elixir
def apply_operation(data, {:rename_file_entry, _client_id, name, new_name}) do
  with {:ok, file_entry} <- fetch_file_entry(data.notebook, name),
       {:ok, file_entry} <- Notebook.rename_file_entry(data.notebook, file_entry, new_name) do
    data
    |> rename_file_entry(file_entry, new_name)
  end
end
```

When `with` fails, the **first non-matching result is returned directly** (no `else` clause). This works because callers pattern-match on the result.

---

## 4. `try` / `rescue` — Scoped to Boundary Code

`try/rescue` is used **sparingly** — mainly at I/O boundaries, external callbacks, and evaluation code.

### File operations (`lib/livebook/session.ex` lines 837-849):
```elixir
defp copy_file(source_path, {:file, file_pid}) do
  try do
    source_path
    |> File.stream!(64_000, [])
    |> Enum.each(fn chunk -> IO.binwrite(file_pid, chunk) end)
    :ok
  rescue
    error -> {:error, "copying file failed, reason: #{inspect(error)}"}
  after
    File.close(file_pid)
  end
end
```

### Smart cell callbacks (`lib/livebook/runtime/erl_dist/runtime_server.ex` lines 510-515):
```elixir
try do
  smart_cell_info.scan_eval_result.(smart_cell_info.pid, result)
rescue
  error -> Logger.error("scanning evaluation result raised an error: #{inspect(error)}")
end
```

### Graceful stop on lost connection (lines 331-334):
```elixir
def stop(pid) do
  GenServer.stop(pid)
catch
  :exit, _ -> :ok
end
```

### Fallback on port-in-use (`lib/livebook/application.ex` lines 230-238):
```elixir
with {:error, {:shutdown, ...}} <- apply(mod, fun, args) do
  Logger.warning("Starting server using a random port")
  endpoint_start({mod, fun, args})  # retry with port 0
end
```

---

## 5. Error Translation — How Domain Errors Map to HTTP Responses

### Web layer: `render_errors` configuration

**`config/config.exs` (line 10):**
```elixir
render_errors: [formats: [html: LivebookWeb.ErrorHTML], layout: false]
```

Only HTML error rendering is configured. No JSON fallback for the main endpoint (though `ErrorJSON` exists).

### `ErrorHTML` (`lib/livebook_web/controllers/error_html.ex`)

Pattern-matches on specific status codes:

```elixir
def render("404.html", assigns), do: ...
def render("403.html", assigns), do: ...
def render("401.html", assigns), do: ...
def render("503.html", assigns), do: ...
def render("unsupported_version.html", assigns), do: ...
def render(_template, assigns), do: ...  # catch-all
```

Each renders a component `<.error_page>` with a branded status page.

### `ErrorJSON` (`lib/livebook_web/controllers/error_json.ex`)
```elixir
def render(template, _assigns) do
  %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
end
```

Simple JSON errors — only used for API routes (`/dev`, `/public/health`).

### ProxyPlug — raises exceptions that Phoenix turns into HTTP responses

**`lib/livebook_web/plugs/proxy_plug.ex`:**
```elixir
raise NotFoundError, "could not find an app session with id #{inspect(id)}"
raise LivebookWeb.BadRequestError, "the requested app is multi-session..."
```

The `plug_status` field on the exception struct drives the HTTP status code automatically. No `action_fallback` usage anywhere.

### No `action_fallback` — controllers are minimal

Livebook has **no controller-level `action_fallback`**. Its controller surface is tiny (asset serving, auth, health). The heavy lifting is in LiveView, not controllers.

---

## 6. Notebook Evaluation Error Handling — Full Flow

This is the most sophisticated error handling in Livebook.

### Step 1: Evaluation catches all errors

**`lib/livebook/runtime/evaluator.ex` (lines 645-687):**
```elixir
defp eval_elixir(code, binding, env) do
  {{result, extra_diagnostics}, diagnostics} =
    Code.with_diagnostics([log: true], fn ->
      try do
        quoted = Code.string_to_quoted!(code, file: env.file)
        try do
          {value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env, opts)
          {:ok, value, binding, env}
        catch
          kind, error ->
            {:error, kind, error, prune_stacktrace(:elixir_eval, __STACKTRACE__)}
        end
      catch
        kind, error ->
          {:error, kind, error, []}
      end
      |> case do
        {:ok, value, binding, env} -> {{:ok, value, binding, env}, []}
        {:error, kind, error, stacktrace} -> {{:error, kind, error, stacktrace}, extra_diagnostics}
      end
    end)
  # ...
end
```

**Nested `try/catch`**: Inner catches evaluation errors (with stacktrace), outer catches parse errors (without stacktrace). `Code.with_diagnostics` captures compiler diagnostics into structured `code_markers`.

### Step 2: Result type

**`lib/livebook/runtime/evaluator.ex` (lines 53-55):**
```elixir
@type evaluation_result ::
        {:ok, result :: any()}
        | {:error, Exception.kind(), error :: any(), Exception.stacktrace()}
```

A **triple** `{:error, kind, error, stacktrace}` rather than a simple `{:error, reason}` — preserves full exception information.

### Step 3: Context-annotated errors

**`lib/livebook/runtime/evaluator/formatter.ex` (lines 242-254):**
```elixir
defp error_context(%System.EnvError{env: "LB_" <> secret_name}),
  do: {:missing_secret, secret_name}

defp error_context(error) when is_struct(error, Kino.InterruptError),
  do: {:interrupt, error.variant, error.message}

defp error_context(error) when is_struct(error, Kino.FS.ForbiddenError),
  do: {:file_entry_forbidden, error.name}

defp error_context(error) when is_struct(error, Mix.Error),
  do: :dependencies

defp error_context(_), do: nil
```

Errors carry a `context` field in the output map. The frontend uses this context to render **interactive widgets** (Add Secret button, Review Access button, Continue button for interrupts).

### Step 4: Frontend renders specialized UIs per error context

**`lib/livebook_web/live/output.ex`:**
- `{:missing_secret, secret_name}` → shows "Missing secret" + "Add secret" button (lines 260-281)
- `{:file_entry_forbidden, file_entry_name}` → shows "Forbidden access" + "Review access" button (lines 283-312)
- `{:interrupt, variant, message}` → shows continue button with variant styling (lines 314-344)
- `:dependencies` → shows "Setup without cache" option on the main setup cell (lines 349-379)
- Generic `:error` → plain error message (line 382)

### Step 5: Errors flow through PubSub

**`lib/livebook/session.ex` (lines 2831-2837):**
```elixir
defp broadcast_error(session_id, error) do
  broadcast_message(session_id, {:error, error})
end

defp broadcast_message(session_id, message) do
  Phoenix.PubSub.broadcast(Livebook.PubSub, "sessions:#{session_id}", message)
end
```

Runtime errors → evaluator → `{:runtime_evaluation_response, ref, output, metadata}` → session processes it → broadcast to LiveView subscribers.

---

## 7. Logging of Errors

### Logger configuration

**`config/config.exs` (lines 13-15):**
```elixir
config :logger, :default_formatter,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:request_id]
```

**`config/test.exs` (lines 21-28)** — structured JSON logging with `logger_json`:
```elixir
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

### Structured log messages

Log messages are **semantically tagged with brackets**:
```elixir
Logger.error("[file_system=#{name(file_system)}] failed to mount: #{reason}")
Logger.error("[app=#{deployment.slug}] Deployment failed, #{message}")
Logger.warning("[app=#{app_spec.slug}] App warmup failed, #{message}")
Logger.error("[app=#{deployment.slug}] Deployment failed, #{message}")
```

### Error logging patterns across the codebase

| Pattern | File | Line |
|---------|------|------|
| Smart cell failure | `runtime/erl_dist/runtime_server.ex` | 628 |
| Evaluation scan error | `runtime/erl_dist/runtime_server.ex` | 514, 891 |
| Formatter crash during output | `runtime/evaluator/formatter.ex` | 71, 118 |
| File mount failures | `file_system/mounter.ex` | 99, 113 |
| Teams WebSocket errors | `teams/connection.ex` | 51-141 |
| Python intellisense error | `intellisense/python.ex` | 490 |
| Hub startup failure | `hubs.ex` | 178 |
| Version check failure | `update_check.ex` | 91, 99 |

**Key pattern**: Logger is used for **diagnostic/logging purposes only** — errors are always **returned as tuples**, not swallowed by logging.

---

## 8. Validation Patterns

Livebook uses **Ecto Changesets** for structured validation, even though Livebook has no database. Changesets are used purely for their validation pipelines.

### App Settings validation (`lib/livebook/notebook/app_settings.ex` lines 80-103):
```elixir
defp changeset(settings, attrs) do
  settings
  |> cast(attrs, [:slug, :multi_session, :auto_shutdown_ms, :access_type, ...])
  |> validate_required([:slug, :multi_session, :access_type, ...])
  |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
       message: "should only contain lowercase alphanumeric characters and dashes")
  |> cast_access_attrs(attrs)
  |> cast_mode_specific_attrs(attrs)
  |> put_defaults()
end
```

### Custom validators in `Livebook.Utils` (`lib/livebook/utils.ex` lines 270-304):
```elixir
def validate_url(changeset, field, opts \\ []) do
  Ecto.Changeset.validate_change(changeset, field, fn ^field, url ->
    if valid_url?(url, opts), do: [], else: [{field, "must be a valid URL"}]
  end)
end
```

### User validation (`lib/livebook/users.ex`):
```elixir
def update_user(%User{} = user, attrs) do
  changeset = User.changeset(user, attrs)
  with {:ok, user} <- Ecto.Changeset.apply_action(changeset, :update) do
    broadcast_change(user)
    {:ok, user}
  end
end
```

### File entry name validation (`lib/livebook/notebook.ex` lines 972-979):
```elixir
def validate_file_entry_name(changeset, field) do
  changeset
  |> Ecto.Changeset.validate_format(field, ~r/^[\w\-\.]+$/,
       message: "should contain only alphanumeric characters, dash, underscore and dot")
  |> Ecto.Changeset.validate_format(field, ~r/\.\w+$/,
       message: "should end with an extension")
end
```

### K8s Pod template validation (`lib/livebook/k8s/pod.ex` lines 121-180):
Uses `with` and pattern matching on maps — no Changesets — to validate Pod YAML manifests.

---

## 9. GenServer Error Handling — `handle_info({:DOWN, ...})`

**`lib/livebook/session.ex` (lines 1664-1723):**

Every monitored process failure is caught via `{:DOWN, ref, :process, pid, reason}`:

```elixir
def handle_info({:DOWN, ref, :process, _, reason}, state)
    when ref == state.runtime_connect.ref do
  broadcast_error(state.session_id,
    "connecting runtime failed unexpectedly - #{Exception.format_exit(reason)}")
  {:noreply, %{state | runtime_connect: nil}
   |> handle_operation({:runtime_down, @client_id})}
end
```

Seven different `:DOWN` handlers, each specific to a monitored process (runtime connect, runtime monitor, save task, deployment, app monitor, etc.). Errors are **broadcast to clients** and **state transitions are applied** via `handle_operation`.

---

## 10. Key Patterns Summary

| Pattern | Prevalence | Example |
|---------|-----------|---------|
| `{:ok, _}` / `{:error, _}` tuples | **Dominant** across all service/business logic | `sessions.ex`, `session.ex`, `users.ex` |
| `with` chains (no `else`) | Heavy usage for sequential validation | `k8s/pod.ex`, `session/data.ex` |
| `try/rescue` | Scoped to I/O, external callbacks, evaluation | `evaluator.ex`, `file_system/*` |
| Custom `defexception` | Small set (5 total), with `plug_status` | `errors.ex`, `storage.ex`, `learn.ex` |
| `Plug.Exception` | Not used — `plug_status` field suffices | — |
| `action_fallback` | **Not used** | — |
| `dry-monads` / custom results | **Not used** | — |
| Changesets for validation | Heavy usage (no DB, purely for validation) | `app_settings.ex`, `users.ex`, `notebook.ex` |
| Context-annotated errors | Unique pattern for notebook evaluation | `formatter.ex` → `output.ex` |
| Logging | Semantic bracket tags, structured JSON in test | `Logger.error("[app=...] ...")` |

### Architectural takeaways

1. **Boundary errors** (HTTP-facing) use exceptions with `plug_status`. Everything else uses tuples.
2. **Evaluation errors** are the most nuanced — they flow through a pipeline: `catch` → `format` → `annotate-with-context` → `PubSub broadcast` → `LiveView render` → `specialized UI widgets`.
3. **No dry-monads, no `action_fallback`**. Livebook stays close to Elixir/OTP conventions.
4. **Changesets without databases** — Ecto Changesets are used purely as declarative validation pipelines.
5. **GenServer `:DOWN` messages** are the backbone of runtime error recovery (runtime disconnects, deployment failures, process crashes).
