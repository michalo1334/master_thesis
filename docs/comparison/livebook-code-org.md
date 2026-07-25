# Livebook Code Organization & Design Patterns

> Based on exploration of `/tmp/comparison_repos/livebook` (commit as of July 2026).

---

## 1. Module Structure

### `lib/livebook/` — Core Domain (48 entries)

```
lib/livebook/
├── apps.ex / apps/            # App lifecycle (deployable notebooks)
├── config.ex                  # Runtime config, feature flags, auth
├── ecto_types/                # Custom Ecto types (HexColor)
├── epmd.ex / epmd/            # Custom EPMD (Erlang Port Mapper Daemon)
├── file_system.ex / file_system/  # File system abstraction (local, S3, Git)
├── hubs.ex / hubs/            # "Hub" connection management (Teams, Personal)
├── intellisense.ex / intellisense/ # Code intelligence (Elixir, Erlang, Python)
├── notebook.ex / notebook/    # Core data structures (Notebook, Section, Cell)
├── runtime.ex / runtime/      # POLYMORPHIC runtime abstraction (protocol)
├── secrets.ex / secrets/      # Secret management
├── session.ex / session/      # Session GenServer + Data + DataSync
├── sessions.ex                # Session registry (CRUD)
├── settings.ex / settings/    # User settings
├── storage.ex                 # ETS-backed persistent storage
├── tracker.ex                 # Phoenix.Tracker for multi-node discovery
├── users.ex / users/          # User management
├── utils.ex / utils/          # Shared utilities
└── (other top-level modules)
```

### `lib/livebook_web/` — Phoenix Web Layer

```
lib/livebook_web/
├── channels/          # Phoenix Channels (if any)
├── components/        # CoreComponents, FormComponents, Layouts
├── controllers/       # SessionController, AuthController, etc.
├── endpoint.ex        # LivebookWeb.Endpoint
├── live/              # All LiveViews
│   ├── session_live/  # Main notebook editing LiveView (heaviest)
│   ├── home_live/     # Home/dashboard
│   ├── settings_live/ # Settings pages
│   ├── hub/           # Hub management LiveViews
│   ├── app_live.ex    # App viewing LiveView
│   └── ...
├── plugs/             # AuthPlug, UserPlug
├── router.ex          # Routes (two live_sessions: :default and :apps)
└── telemetry.ex
```

**Key observation:** No `Phoenix.Context` modules (like `Accounts`, `Catalog`). Domain logic lives under `lib/livebook/` directly, organized by concept (not by bounded context). There is no `lib/livebook/accounts/` or similar. Instead:

- `Livebook.Hubs` acts like a context for hub/provider management
- `Livebook.Sessions` is the "context" for session CRUD
- `Livebook.Runtime` is a protocol, not a context

---

## 2. Ecto Usage Without a Database

Livebook uses `Ecto.Schema` + `embedded_schema` extensively but **never** with a database repo. They use Ecto purely for:

1. **Changeset validation** (type casting, required fields)
2. **Serialization** via `Ecto.Changeset` and custom dump/load
3. **Custom Ecto types** (e.g., `Livebook.EctoTypes.HexColor`)

Schemas are persisted via `Livebook.Storage` (ETS + file sync), not via Ecto.Repo.

```elixir
# lib/livebook/users/user.ex (lines 10-39)
defmodule Livebook.Users.User do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :name, :string
    field :email, :string
    field :avatar_url, :string
    field :access_type, Ecto.Enum, values: ~w[full apps]a, default: :full
    field :groups, {:array, :map}, default: []
    field :payload, :map
    field :hex_color, Livebook.EctoTypes.HexColor
  end

  def changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:name, :email, :avatar_url, :access_type, :groups, :hex_color, :payload])
    |> validate_required([:hex_color])
  end
end
```

**19 embedded schemas** found across the codebase:

| Path | Module |
|------|--------|
| `users/user.ex` | `Livebook.Users.User` |
| `secrets/secret.ex` | `Livebook.Secrets.Secret` |
| `hubs/personal.ex` | `Livebook.Hubs.Personal` |
| `hubs/team.ex` | `Livebook.Hubs.Team` (+ nested `Offline`) |
| `settings/env_var.ex` | `Livebook.Settings.EnvVar` |
| `file_system/s3.ex` | `Livebook.FileSystem.S3` |
| `file_system/git.ex` | `Livebook.FileSystem.Git` |
| `notebook/app_settings.ex` | `Livebook.Notebook.AppSettings` |
| `k8s/pvc.ex` | `Livebook.K8s.PVC` |
| `teams/*.ex` | 7 team-related schemas |

### `Livebook.Storage` — ETS + File Persistence

```elixir
# lib/livebook/storage.ex (lines 1-9, simplified)
defmodule Livebook.Storage do
  use GenServer
  # Uses an ETS table synchronized to a file.
  # Entity-Attribute-Value model.
  # insert/delete go through the GenServer.
  # Lookups via direct ETS access.
end
```

Storage is namespace-based: `Storage.all(:hubs)`, `Storage.fetch(:hubs, id)`. No SQL, no Ecto.Repo — the ETS table is persisted to a JSON file.

---

## 3. Runtime Abstraction — Protocol Pattern

This is the most architecturally significant pattern. Code evaluation is abstracted via an **Elixir Protocol** (`defprotocol`), with multiple struct implementations.

### Protocol Definition

```elixir
# lib/livebook/runtime.ex (line 1)
defprotocol Livebook.Runtime do
  @spec describe(t()) :: list({label :: String.t(), String.t()})
  def describe(runtime)

  @spec connect(t()) :: pid()
  def connect(runtime)

  @spec take_ownership(t(), keyword()) :: reference()
  def take_ownership(runtime, opts)

  @spec evaluate_code(t(), language(), String.t(), locator(), parent_locators(), keyword()) :: :ok
  def evaluate_code(runtime, language, code, locator, parent_locators, opts)

  @spec handle_intellisense(t(), pid(), language(), request(), parent_locators(), node) :: reference()
  def handle_intellisense(runtime, send_to, language, request, parent_locators, node)

  # ... ~30 protocol functions total
end
```

### Implementations

Each runtime type is a **struct** + a `defimpl` block:

| Struct | File | Description |
|--------|------|-------------|
| `Livebook.Runtime.Standalone` | `runtime/standalone.ex` | Spawns a child Elixir node via OS process |
| `Livebook.Runtime.Embedded` | `runtime/embedded.ex` | Runs in the same BEAM node as Livebook |
| `Livebook.Runtime.Attached` | `runtime/attached.ex` | Connects to an externally managed node |
| `Livebook.Runtime.Fly` | `runtime/fly.ex` | Runtime on Fly.io platform |
| `Livebook.Runtime.K8s` | `runtime/k8s.ex` | Runtime on Kubernetes |

### Standalone Implementation Pattern

```elixir
# lib/livebook/runtime/standalone.ex (lines 1-3, 238-362)

# 1. Define the struct
defmodule Livebook.Runtime.Standalone do
  defstruct [:erl_flags, :node, :server_pid]

  def new(opts \\ []) do
    %__MODULE__{erl_flags: opts[:erl_flags]}
  end

  # Internal connect function (called by the protocol impl)
  def __connect__(runtime) do
    caller = self()
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Livebook.RuntimeSupervisor,       # <-- supervision!
        {Task, fn -> do_connect(runtime, caller) end}
      )
    pid
  end
end

# 2. Implement the protocol
defimpl Livebook.Runtime, for: Livebook.Runtime.Standalone do
  alias Livebook.Runtime.ErlDist.RuntimeServer

  def connect(runtime), do: Livebook.Runtime.Standalone.__connect__(runtime)

  def take_ownership(runtime, opts) do
    RuntimeServer.attach(runtime.server_pid, self(), opts)
    Process.monitor(runtime.server_pid)
  end

  def evaluate_code(runtime, language, code, locator, parent_locators, opts) do
    RuntimeServer.evaluate_code(runtime.server_pid, language, code, locator, parent_locators, opts)
  end

  # All other functions delegate to RuntimeServer
end
```

### How All Runtimes Share Logic

All three local runtime types (Standalone, Embedded, Attached) delegate to `Livebook.Runtime.ErlDist.RuntimeServer`:

```elixir
# lib/livebook/runtime/erl_dist/runtime_server.ex (line 1)
defmodule Livebook.Runtime.ErlDist.RuntimeServer do
  use GenServer, restart: :temporary

  # Handles evaluate_code, forget_evaluation, drop_container,
  # handle_intellisense, read_file, transfer_file, smart_cells, etc.
  # Spawns Evaluator processes per container.
end
```

The `RuntimeServer` is the true workhorse. It spawns `Evaluator` processes (one per evaluation container), manages their lifecycle, and relays messages between the session owner and the evaluators.

---

## 4. Session Management — GenServer with Operation-Log Pattern

`Livebook.Session` is the central GenServer (~3579 lines). It uses a unique **operation-log pattern** for state synchronization.

### Architecture

```
Client (LiveView) ←→ Session GenServer ←→ Runtime (protocol)
                          │
                    Session.Data (pure struct)
                          │
                    Operations broadcast via PubSub
                          │
                    All clients apply ops locally
```

### Key Design Decisions

```elixir
# lib/livebook/session.ex (lines 1-99)
defmodule Livebook.Session do
  use GenServer, restart: :temporary   # sessions are transient

  @main_container_ref :main_flow        # single main evaluation process

  defstruct [:id, :pid, :origin, :notebook_name, :file, :mode, ...]
end
```

**Line 84:** `use GenServer, restart: :temporary` — each session is started under a `DynamicSupervisor` and not restarted on failure.

### Operation-Log State Management

All state changes go through `Data.apply_operation/2`:

```elixir
# lib/livebook/session/data.ex (lines 193-260)
@type operation ::
  {:set_notebook_attributes, client_id, map()}
  | {:insert_section, client_id, index, section_id}
  | {:queue_cells_evaluation, client_id, list(cell_id), keyword()}
  | {:set_runtime, client_id, Runtime.t()}
  | {:connect_runtime, client_id}
  | ...  # ~50 operation types
```

The session applies operations and broadcasts them to all connected clients:

```elixir
# Pattern in handle_cast/handle_info:
def handle_cast({:insert_cell, client_pid, section_id, index, type, attrs}, state) do
  client_id = client_id(state, client_pid)
  operation = {:insert_cell, client_id, section_id, index, type, Livebook.Utils.random_id(), attrs}
  {:noreply, handle_operation(state, operation)}
end
```

### Runtime Lifecycle in Session

```elixir
# Session init (lines 936-978)
def init({caller_pid, opts}) do
  # ...
  {:ok, worker_pid} = Livebook.Session.Worker.start_link(id)  # helper process
  # ... sets up data, tracks session via Phoenix.Tracker
  if state.data.mode == :app do
    {:ok, state, {:continue, :app_init}}  # app sessions auto-evaluate
  else
    {:ok, state}
  end
end
```

Runtime connect is async via the protocol:
1. Session calls `Runtime.connect(runtime)` → gets a pid
2. The connect process sends `{:runtime_connect_done, pid, result}` on completion
3. Session takes ownership via `Runtime.take_ownership/2`
4. Runtime sends evaluation outputs as `{:runtime_evaluation_output, ref, output}`

---

## 5. Supervision Trees

### Top-Level Application Supervisor

```elixir
# lib/livebook/application.ex (lines 19-68)
children = [
  LivebookWeb.Telemetry,
  {Phoenix.PubSub, name: Livebook.PubSub},
  {Task.Supervisor, name: Livebook.TaskSupervisor},
  Livebook.Utils.UniqueTask,
  Livebook.Storage,
  {Livebook.Utils.SupervisionStep, {:migration, &Livebook.Migration.run/0}},
  Livebook.UpdateCheck,
  Livebook.SystemResources,
  Livebook.NotebookManager,
  {Livebook.Tracker, pubsub_server: Livebook.PubSub},
  Livebook.EPMD.NodePool,
  Livebook.Session.FileGuard,
  {DynamicSupervisor, name: Livebook.RuntimeSupervisor, strategy: :one_for_one},  # KEY
  {DynamicSupervisor, name: Livebook.SessionSupervisor, strategy: :one_for_one},  # KEY
  {Registry, keys: :unique, name: Livebook.HubsRegistry},
  {DynamicSupervisor, name: Livebook.HubsSupervisor, strategy: :one_for_one},
  {Livebook.Utils.SupervisionStep, {:boot, boot(create_teams_hub)}},
  Livebook.FileSystem.Mounter,
  Livebook.Apps.DeploymentSupervisor
]
```

### Key Dynamic Supervisors

```
Livebook.Supervisor (one_for_one)
├── Livebook.RuntimeSupervisor (DynamicSupervisor)
│   └── Task (runtime connect processes)     ← transient, per-connection
├── Livebook.SessionSupervisor (DynamicSupervisor)
│   └── Livebook.Session (GenServer)         ← :temporary restart
├── Livebook.HubsSupervisor (DynamicSupervisor)
│   └── Hub provider processes
└── Livebook.Apps.DeploymentSupervisor
    └── Livebook.App processes               ← via :global name registration
```

**Session lifecycle:** `Livebook.Sessions.create_session/1` starts a child under `SessionSupervisor`. On shutdown/disconnect, the session GenServer stops (not restarted).

**Runtime lifecycle:** Each runtime type implements `connect/1` which starts a `Task` under `RuntimeSupervisor`. The connect task initializes the runtime (possibly spawning OS processes), then the caller takes ownership by monitoring the runtime server.

---

## 6. Multi-Node State — Phoenix.Tracker

```elixir
# lib/livebook/tracker.ex (lines 1-120)
defmodule Livebook.Tracker do
  use Phoenix.Tracker

  @sessions_topic "sessions"
  @apps_topic "apps"

  def track_session(session) do
    Phoenix.Tracker.track(@name, session.pid, @sessions_topic, session.id, %{session: session})
  end

  def list_sessions() do
    presences = Phoenix.Tracker.list(@name, @sessions_topic)
    for {_id, %{session: session}} <- presences, do: session
  end
end
```

`Phoenix.Tracker` provides **distributed presence** on top of `Phoenix.PubSub`. Sessions are tracked by their pid, and the tracker gossips across nodes. This is how Livebook knows about all sessions in the cluster.

Session IDs are **node-aware**:

```elixir
# lib/livebook/sessions.ex (line 16)
id = Livebook.Utils.random_node_aware_id()
# Encodes the boot_id and node into the ID for cross-node routing
```

---

## 7. Session Data Synchronization Pattern

`Session.Data` is the pure state struct. All changes happen via **operations** — tagged tuples that are:

1. Applied by the session GenServer (source of truth)
2. Broadcast via PubSub to all clients
3. Applied locally by each client to keep their copy in sync

```elixir
# lib/livebook/session/data.ex (lines 1-17, 276-285)
defmodule Livebook.Session.Data do
  # Session data is a Notebook decorated with ephemeral session data.
  # All changes go through the Session process to introduce linearity,
  # then are broadcast to clients so every client receives changes
  # in the same order.

  defstruct [:notebook, :section_infos, :cell_infos, :runtime, :runtime_status, ...]

  def new(opts \\ []) do
    # Sets default runtime based on mode (:default vs :app)
    default_runtime = if opts[:mode] == :app do
      Livebook.Config.default_app_runtime()
    else
      Livebook.Config.default_runtime()
    end
    # ...
  end
end
```

The `DataSync` module handles syncing an external notebook into session state:

```elixir
# lib/livebook/session/data_sync.ex (line 1)
defmodule Livebook.Session.DataSync do
  def sync(data, updated_notebook, client_id) do
    sync_notebook_attrs(data.notebook, updated_notebook, client_id) ++
    sync_setup_section(data, updated_notebook, client_id) ++
    sync_sections_and_cells(data, updated_notebook, client_id)
  end
end
```

---

## 8. Feature Flags

```elixir
# lib/livebook/config.ex (lines 356-380)
@feature_flags Application.compile_env(:livebook, :feature_flags)

def feature_flags(), do: @feature_flags

def enabled_feature_flags() do
  for {flag, enabled?} <- feature_flags(), enabled?, do: flag
end

def feature_flag_enabled?(key) do
  Keyword.get(@feature_flags, key, false)
end
```

Feature flags are **compile-time configured** via application config and exposed to the frontend:

```heex
<%# lib/livebook_web/components/layouts/root.html.heex (line 36) %>
data-feature-flags={Livebook.Config.enabled_feature_flags() |> Enum.join(",")}
```

---

## 9. App Mode Patterns — Desktop vs Server

### Server vs "Serverless" (App Mode)

```elixir
# lib/livebook/application.ex (lines 444-446)
defp serverless?() do
  Application.get_env(:livebook, :serverless, false)
end
```

When `serverless: true`, the web endpoint and most infrastructure is not started — only the core domain (storage, sessions, runtimes).

### Desktop App Mode

```elixir
# lib/livebook_app.ex (lines 1-51, conditionally compiled)
if Mix.target() == :app do
  defmodule LivebookApp do
    use GenServer
    # Handles desktop-specific messages:
    # "open:/logs", "open:/boot-script", "open:<url>"
    # Monitors ElixirKit.PubSub for lifecycle
  end
end
```

Desktop mode uses `Mix.target() == :app` for compile-time conditionals:

```elixir
# lib/livebook/application.ex (lines 198-224)
@app? Mix.target() == :app

if @app? do
  defp app_specs do
    [{ElixirKit.PubSub, ...}, LivebookApp]
  end
  defp endpoint_childspec(opts) do
    # Auto-fallback to random port if :eaddrinuse
  end
else
  defp app_specs, do: []
  defp endpoint_childspec(opts), do: LivebookWeb.Endpoint.child_spec(opts)
end
```

### Runtime Type Gating

```elixir
# lib/livebook.ex (lines 178-192)
config :livebook, :default_runtime, Livebook.Runtime.Standalone.new()
config :livebook, :default_app_runtime, Livebook.Runtime.Standalone.new()
config :livebook, :runtime_modules, [
  Livebook.Runtime.Standalone,
  Livebook.Runtime.Attached,
  Livebook.Runtime.Fly,
  Livebook.Runtime.K8s
]
```

Notably, `Livebook.Runtime.Embedded` is **not** in the default `:runtime_modules` list — it can only be used if explicitly set as `:default_runtime` or configured via the `LIVEBOOK_DEFAULT_RUNTIME=embedded` env var.

```elixir
# lib/livebook/config.ex (lines 72-76)
def runtime_enabled?(runtime) do
  runtime in Application.fetch_env!(:livebook, :runtime_modules) or
    runtime == default_runtime().__struct__
end
```

---

## 10. Dependency Injection Patterns

Livebook avoids explicit DI frameworks. Instead:

### A. Application Config for Runtime Defaults

```elixir
# lib/livebook/config.ex (lines 56-67)
def default_runtime() do
  Application.fetch_env!(:livebook, :default_runtime)
end

def default_app_runtime() do
  Application.fetch_env!(:livebook, :default_app_runtime)
end
```

### B. Config for Embedded Runtime Packages

```elixir
# lib/livebook.ex (lines 24-37)
config :livebook, Livebook.Runtime.Embedded,
  load_packages: {Loader, :packages, []}

# Used in runtime/embedded.ex (lines 140-143)
def packages_source(_runtime) do
  {mod, fun, args} = config()[:load_packages]
  packages = apply(mod, fun, args)
  {:list, packages}
end
```

### C. `:persistent_term` for Global State

```elixir
# lib/livebook/application.ex (lines 125-132)
defp set_local_file_system!() do
  home = Livebook.Config.home() |> Livebook.FileSystem.Utils.ensure_dir_path()
  local_file_system = Livebook.FileSystem.Local.new(default_path: home)
  :persistent_term.put(:livebook_local_file_system, local_file_system)
end
```

### D. EPMD Injection via Environment

The custom EPMD module is injected at boot:

```elixir
# lib/livebook/application.ex (lines 134-157)
defp set_epmd_module!() do
  Application.put_env(:kernel, :epmd_module, Livebook.EPMD, persistent: true)
  # Or via ELIXIR_ERL_OPTIONS="-epmd_module Elixir.Livebook.EPMD"
end
```

---

## 11. File System Abstraction

`Livebook.FileSystem` is a **protocol** (like Runtime):

| Implementation | Description |
|----------------|-------------|
| `FileSystem.Local` | Local filesystem |
| `FileSystem.S3` | AWS S3 (embedded_schema) |
| `FileSystem.Git` | Git-based (embedded_schema) |

Files are referenced via `FileSystem.File.t()` structs that carry the type information. The protocol handles operations like `read`, `write`, `cp`, `mv`.

---

## 12. Summary of Key Patterns

| Pattern | Where | How |
|---------|-------|-----|
| **Protocol for polymorphism** | `Runtime`, `FileSystem`, `ContentLoader` | `defprotocol` + `defimpl` per struct |
| **Ecto without DB** | 19 modules | `embedded_schema` + `Ecto.Changeset` for validation only |
| **ETS + file persistence** | `Livebook.Storage` | GenServer + ETS table synced to JSON file |
| **Operation-log state** | `Session.Data` | Operations are tuples, applied atomically, broadcast via PubSub |
| **Operations as data** | `Session.Data.apply_operation/2` | ~50 operation types; `apply_operation` returns `{:ok, data, actions}` |
| **Dynamic supervision** | `RuntimeSupervisor`, `SessionSupervisor` | `DynamicSupervisor` + `:temporary` restart |
| **Multi-node discovery** | `Livebook.Tracker` | `Phoenix.Tracker` for distributed presence |
| **Compile-time conditionals** | Desktop vs server | `Mix.target() == :app` at module level |
| **Feature flags** | `Livebook.Config` | `Application.compile_env` + keyword list |
| **Notebook as data** | `Notebook`, `Section`, `Cell` | Pure structs, no processes |
