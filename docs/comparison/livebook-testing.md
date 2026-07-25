# Livebook Testing Practices

> Analysis of `/tmp/comparison_repos/livebook/test/` — a production Elixir/Phoenix
> LiveView application (notebook editor). ~92 test files, ~230KB of test code.

---

## 1. Test Directory Structure

```
test/
  test_helper.exs              # Global test bootstrap
  support/                     # Shared modules compiled in :test env
    data_case.ex               # Data layer case template
    conn_case.ex               # Conn/LiveView case template
    channel_case.ex             # Phoenix Channel case template
    teams_integration_case.ex  # Teams integration case template
    factory.ex                 # Custom factory (no ExMachina)
    session_helpers.ex         # Session/notebook operation helpers
    test_helpers.ex            # General-purpose test utilities
    app_helpers.ex             # App deployment helpers
    hub_helpers.ex             # Hubs & offline hub helpers
    file_system_helpers.ex     # S3 ID helper
    noop_runtime.ex            # Noop runtime for fast tests
    k8s_cluster_stub.ex        # Plug-based K8s API stub
    integration/               # Teams integration support
    notebooks/                 # Sample .livemd fixtures
    test_modules/              # Compiled test-only modules
    static/                    # Static test assets
    assets.tar.gz              # Test JS assets archive

  livebook/                    # Unit tests for lib/livebook/
    session_test.exs           # ~2300 lines, Session GenServer tests
    session/
      data_test.exs            # ~5100 lines, Session.Data tests
      data_sync_test.exs
      file_guard_test.exs
    notebook_test.exs
    runtime/                   # Runtime implementations
    hubs/                      # Hub implementations
    ...

  livebook_web/                # Web-layer tests
    live/                      # LiveView integration tests
      home_live_test.exs
      session_live_test.exs    # ~3000 lines
      settings_live_test.exs
      ...
    controllers/               # Controller tests
    channels/                  # Phoenix Channel tests
    plugs/                     # Plug tests
    helpers/                   # View helper tests

  livebook_teams/              # Teams-specific tests
    web/                       # Teams LiveView tests
    cli/                       # CLI tests
    hubs/                      # TeamClient tests
```

**Key pattern**: The test directory mirrors `lib/` structure: `test/livebook/` ↔ `lib/livebook/`, `test/livebook_web/` ↔ `lib/livebook_web/`, `test/livebook_teams/` ↔ `lib/livebook_teams/`.

---

## 2. Test Types

### 2a. Unit Tests (`use ExUnit.Case, async: true`)

Pure logic tests for modules like `Notebook`, `Session.Data`, `Text.Delta`, etc. No
side effects beyond ETS/processes.

**File**: `test/livebook/notebook_test.exs` (line 1-2)

```elixir
defmodule Livebook.NotebookTest do
  use ExUnit.Case, async: true
```

### 2b. Integration Tests (async: false or tagged)

Tests that start runtimes, deploy apps, or interact with external systems.

**File**: `test/livebook/session_test.exs` (lines 2146-2147)

```elixir
# A nested module that must run synchronously
describe "default hub for new notebooks" do
  @describetag async: false
```

Some integration tests are tagged for exclusion and require external infrastructure:

**File**: `test/livebook/runtime/k8s_test.exs` (lines 1-9)

```elixir
defmodule Livebook.Runtime.K8sTest do
  use ExUnit.Case, async: true
  @moduletag :k8s  # excluded by default in test_helper.exs
```

### 2c. LiveView Tests (`use LivebookWeb.ConnCase`)

Tests exercise full LiveView lifecycle: mount, render, event handling, redirects.

**File**: `test/livebook_web/live/home_live_test.exs` (lines 1-15)

```elixir
defmodule LivebookWeb.HomeLiveTest do
  use LivebookWeb.ConnCase, async: true

  test "disconnected and connected render", %{conn: conn} do
    {:ok, view, disconnected_html} = live(conn, ~p"/")
    assert disconnected_html =~ "Running sessions"
    assert render(view) =~ "Running sessions"
  end
```

---

## 3. Factories — Custom Module (no ExMachina)

Livebook does **not** use ExMachina. Instead, they have a hand-rolled `Livebook.Factory`
module at `test/support/factory.ex` with a `build/1`, `build/2`, and `params_for/2` API.

**File**: `test/support/factory.ex` (lines 1-232)

```elixir
defmodule Livebook.Factory do
  def build(:user) do
    %Livebook.Users.User{
      id: Livebook.Utils.random_long_id(),
      name: "Jose Valim",
      hex_color: Livebook.EctoTypes.HexColor.random()
    }
  end

  def build(factory_name, attrs) do
    factory_name |> build() |> struct!(attrs)
  end

  def params_for(factory_name, attrs \\ []) do
    factory_name |> build() |> struct!(attrs) |> Map.from_struct()
  end
```

- `build(factory_name)` — builds a struct with defaults.
- `build(factory_name, attrs)` — merges overrides via `struct!`.
- `params_for(factory_name, attrs)` — same but returns a plain map.
- Factory atoms: `:user`, `:team`, `:personal`, `:secret`, `:env_var`,
  `:deployment_group`, `:org`, `:fs_s3`, `:fs_git`, `:agent_key`,
  `:app_deployment`, `:agent`, `:app_folder`, `:notification`.

Convenience inserters in the same module:

**File**: `test/support/factory.ex` (lines 189-209)

```elixir
def insert_secret(attrs \\ %{}) do
  secret = build(:secret, attrs)
  hub = Livebook.Hubs.fetch_hub!(secret.hub_id)
  :ok = Livebook.Hubs.create_secret(hub, secret)
  secret
end

def insert_env_var(factory_name, attrs \\ %{}) do
  env_var = build(factory_name, attrs)
  attributes = env_var |> Map.from_struct() |> Map.to_list()
  Livebook.Storage.insert(:env_vars, env_var.name, attributes)
  env_var
end
```

Factory is imported in case templates:

**File**: `test/support/data_case.ex` (line 25) and `test/support/conn_case.ex` (line 9)

```elixir
import Livebook.Factory
```

---

## 4. Mocks and Stubs

### 4a. Bypass — HTTP stubbing

Used extensively for HTTP integration tests.

**File**: `test/livebook/session_test.exs` (lines 876-889)

```elixir
test "given :files_source as a url, downloads attached files" do
  bypass = Bypass.open()
  base_url = "http://localhost:#{bypass.port}/files/"

  Bypass.expect_once(bypass, "GET", "/files/image.jpg", fn conn ->
    Plug.Conn.resp(conn, 200, "content")
  end)

  notebook = %{Notebook.new() | file_entries: [%{type: :attachment, name: "image.jpg"}]}
  session = start_session(notebook: notebook, files_source: {:url, base_url})
  # ...
end
```

Also in controller tests:

**File**: `test/livebook_web/controllers/session_controller_test.exs` (lines 113-118)

```elixir
bypass = Bypass.open()
url = "http://localhost:#{bypass.port}/data.csv"

Bypass.expect_once(bypass, "GET", "/data.csv", fn conn ->
  Plug.Conn.resp(conn, 200, "hello")
end)
```

### 4b. NoopRuntime — Stub for Session GenServer tests

A fake runtime that does no actual evaluation. Used to avoid starting expensive
runtime processes in tests.

**File**: `test/support/noop_runtime.ex` (lines 1-85)

```elixir
defmodule Livebook.Runtime.NoopRuntime do
  defstruct [:trace_to]

  defimpl Livebook.Runtime do
    def connect(runtime) do
      caller = self()
      spawn(fn ->
        send(caller, {:runtime_connect_done, self(), {:ok, runtime}})
      end)
    end
    def evaluate_code(_, _, _, _, _, _ \\ []), do: :ok
    # ...
  end
end
```

Usage in tests:

**File**: `test/livebook/session_test.exs` (lines 2292-2295)

```elixir
defp set_noop_runtime(session_pid, trace_to \\ nil) do
  runtime = Livebook.Runtime.NoopRuntime.new(trace_to)
  Session.set_runtime(session_pid, runtime)
end
```

### 4c. K8sClusterStub — Plug-based K8s API stub

For testing K8s integration without a real cluster.

**File**: `test/support/k8s_cluster_stub.ex` (lines 1-70)

```elixir
defmodule Livebook.K8sClusterStub do
  use Plug.Router

  get "/api/v1/namespaces", host: "default" do
    Req.Test.json(conn, %{"items" => [%{"metadata" => %{"name" => "default"}}]})
  end
  # ...
end
```

Configured in `config/test.exs`:

```elixir
config :livebook,
  k8s_kubeconfig_pipeline:
    {Kubereq.Kubeconfig.Stub,
     plugs: %{
       "default" => {Req.Test, :k8s_cluster},
       "no-permission" => {Req.Test, :k8s_cluster}
     }}
```

### 4d. Req.Test for ad-hoc stubbing

Used inline in some tests for one-off HTTP request stubbing.

### 4e. No Mox

They do **not** use Mox. Instead, they rely on:
- `NoopRuntime` (protocol-based stub)
- Direct `send(pid, msg)` to simulate messages from the runtime to the GenServer
- Process assertions (`assert_receive`) to verify side effects

---

## 5. Test Configuration

### 5a. `config/test.exs`

**File**: `config/test.exs` (full file, 49 lines)

```elixir
import Config

# Server disabled during tests
config :livebook, LivebookWeb.Endpoint,
  http: [port: 4002],
  server: false

# Disable authentication
config :livebook,
  authentication: :disabled,
  check_completion_data_interval: 300,
  iframe_port: 4003

# JSON logger for test
config :logger, :default_handler, level: :warning
config :livebook, :logger, [
  {:handler, :json_log, :logger_std_h,
   %{
     config: %{file: ~c"tmp/test.log.json"},
     formatter: {LoggerJSON.Formatters.Basic, %{metadata: [...]}}
   }}
]

# K8s kubeconfig stub
config :livebook,
  k8s_kubeconfig_pipeline: {Kubereq.Kubeconfig.Stub, plugs: %{...}}

# Disable retries for fast tests
config :livebook, Livebook.Apps.Manager, retry_backoff_base_ms: 0
config :livebook, teams_connection_backoff_range_ms: 0..0
```

### 5b. `test/test_helper.exs`

**File**: `test/test_helper.exs` (94 lines)

```elixir
# Embedded runtime by default (cheap)
Application.put_env(:livebook, :default_runtime, Livebook.Runtime.Embedded.new())

# Disable autosaving
Livebook.Storage.insert(:settings, "global", autosave_path: nil)

# Fixed secret key for reproducibility
secret_key = "5ji8DpnX761QAWXZwSl-2Y-mdW4yTcMimdOJ8SSxCh44wFE0jEbGBUf-VydKwnTLzBiAUedQKs3X_q1j_3lgrw"
personal_hub = Livebook.Hubs.fetch_hub!(Livebook.Hubs.Personal.id())
Livebook.Hubs.Personal.update_hub(personal_hub, %{secret_key: secret_key})

# Tag exclusions
ExUnit.start(
  assert_receive_timeout: if(windows?, do: 5_000, else: 1_500),
  exclude: [
    python: nix?,
    git: not git_ssh_key?,
    fly: not fly_api_token?,
    teams_integration: not Livebook.TeamsServer.available?(),
    unix: windows?,
    k8s: true,
    erl_docs: without_docs?
  ]
)
```

### 5c. Compilation paths

**File**: `mix.exs` (line 58)

```elixir
defp elixirc_paths(:test), do: elixirc_paths(:dev) ++ ["test/support"]
```

`test/support/` is compiled as part of the test environment.

---

## 6. Property-Based Testing

**Not used.** There is no `stream_data`, `PropCheck`, or `excheck` dependency in
`mix.exs`. The grep for property-based libraries returned zero matches in
`mix.exs`. All tests are example-based.

---

## 7. Code Coverage

**No coverage tool.** `ExCoveralls` is not present in `mix.exs`. There are no
coverage-related configs or CI steps.

---

## 8. Test Quality

### 8a. `async: true` Usage

**54 out of 54 test modules found use `async: true`**. Only 2 exceptions:
- `Livebook.SessionTest.DefaultHubTest` (nested module, line 2147) uses
  `async: false` because it modifies a global default hub setting.
- `Livebook.Teams.ConnectionTest` uses `async: false` (socket connections).

Every LiveView test file (`ConnCase`-based) uses `async: true`.

### 8b. `describe` Blocks

Heavy use of `describe` for organization. Examples from `notebook_test.exs`:
`fetch_cell_sibling`, `move_cell`, `cell_move_position`, `cell_dependency_graph`,
`find_asset_info`, `add_cell_output`, `find_frame_outputs`.

### 8c. Tags

```elixir
@tag :tmp_dir                    # Creates a temp dir for the test
@moduletag :tmp_dir              # Same for all tests in the module
@tag authentication: %{mode: :password, secret: "grumpycat"}
@describetag authentication: %{mode: :password, secret: "grumpycat"}
@moduletag :k8s                  # Excluded unless explicitly run
```

### 8d. `on_exit` Cleanup

Every test that creates a session uses `on_exit` for cleanup:

**File**: `test/livebook/session_test.exs` (lines 2273-2281)

```elixir
defp start_session(opts \\ []) do
  {:ok, session} = Livebook.Sessions.create_session(opts)
  on_exit(fn ->
    Session.close(session.pid)
  end)
  session
end
```

Same pattern in `setup` blocks:

**File**: `test/livebook_web/live/session_live_test.exs` (lines 11-19)

```elixir
setup do
  {:ok, session} = Sessions.create_session(notebook: Livebook.Notebook.new())
  on_exit(fn ->
    Session.close(session.pid)
  end)
  %{session: session}
end
```

---

## 9. Test Support Modules

| Module | File | Purpose |
|--------|------|---------|
| `Livebook.DataCase` | `test/support/data_case.ex` | Imports Ecto, factory, `errors_on/1` helper |
| `LivebookWeb.ConnCase` | `test/support/conn_case.ex` | Sets up `conn`, auth helpers, LiveView imports |
| `LivebookWeb.ChannelCase` | `test/support/channel_case.ex` | Imports `Phoenix.ChannelTest` |
| `Livebook.TeamsIntegrationCase` | `test/support/teams_integration_case.ex` | Starts Teams server, sets up hubs topics |
| `Livebook.Factory` | `test/support/factory.ex` | Build/insert helpers for structs |
| `Livebook.SessionHelpers` | `test/support/session_helpers.ex` | `wait_for_session_update/1`, `evaluate_cell/2`, etc. |
| `Livebook.TestHelpers` | `test/support/test_helpers.ex` | `create_tree!/2`, `data_after_operations!/2`, `render_confirm/2`, `source_for_blocking/0`, `terminal_text/2` macro |
| `Livebook.AppHelpers` | `test/support/app_helpers.ex` | `deploy_notebook_sync/2`, `deploy_app/8`, `stamp_notebook/2` |
| `Livebook.HubHelpers` | `test/support/hub_helpers.ex` | Offline hub setup, side effects simulation for TeamClient |
| `Livebook.Runtime.NoopRuntime` | `test/support/noop_runtime.ex` | Fake runtime that does nothing |
| `Livebook.K8sClusterStub` | `test/support/k8s_cluster_stub.ex` | Plug-based K8s API stub |
| `Livebook.FileSystemHelpers` | `test/support/file_system_helpers.ex` | S3 ID helper |

### DataCase

**File**: `test/support/data_case.ex`

```elixir
defmodule Livebook.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Livebook.DataCase
      import Livebook.Factory
    end
  end

  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
```

### ConnCase

**File**: `test/support/conn_case.ex`

```elixir
defmodule LivebookWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Livebook.Factory
      import LivebookWeb.ConnCase
      use LivebookWeb, :verified_routes
      @endpoint LivebookWeb.Endpoint
    end
  end

  setup tags do
    conn = Phoenix.ConnTest.build_conn()
    conn = if authentication = tags[:authentication] do
      with_authentication(conn, authentication)
    else
      conn
    end
    [conn: conn]
  end
end
```

---

## 10. LiveView Testing Patterns

### 10a. Basic LiveView mount & render

**File**: `test/livebook_web/live/session_live_test.exs` (lines 21-25)

```elixir
test "disconnected and connected render", %{conn: conn, session: session} do
  {:ok, view, disconnected_html} = live(conn, ~p"/sessions/#{session.id}")
  assert disconnected_html =~ "Untitled notebook"
  assert render(view) =~ "Untitled notebook"
end
```

### 10b. Interacting with elements

**File**: `test/livebook_web/live/session_live_test.exs` (lines 94-101)

```elixir
test "adding a new section", %{conn: conn, session: session} do
  {:ok, view, _} = live(conn, ~p"/sessions/#{session.id}")

  view
  |> element("button", "New section")
  |> render_click()

  assert %{notebook: %{sections: [_section]}} = Session.get_data(session.pid)
end
```

### 10c. LiveView hooks (events)

**File**: `test/livebook_web/live/session_live_test.exs` (lines 117-135)

```elixir
test "queueing cell evaluation", %{conn: conn, session: session} do
  Session.subscribe(session.id)
  evaluate_setup(session.pid)

  section_id = insert_section(session.pid)
  {source, continue_fun} = source_for_blocking()
  cell_id = insert_text_cell(session.pid, section_id, :code, source)

  {:ok, view, _} = live(conn, ~p"/sessions/#{session.id}")

  view
  |> element(~s{[data-el-session]})
  |> render_hook("queue_cell_evaluation", %{"cell_id" => cell_id})

  assert %{cell_infos: %{^cell_id => %{eval: %{status: :evaluating}}}} =
           Session.get_data(session.pid)

  continue_fun.()
end
```

### 10d. Asynchronous update assertions

**File**: `test/livebook_web/live/session_live_test.exs` (lines 27-35)

```elixir
describe "asynchronous updates" do
  test "renders an updated notebook name", %{conn: conn, session: session} do
    {:ok, view, _} = live(conn, ~p"/sessions/#{session.id}")

    Session.set_notebook_name(session.pid, "My notebook")
    wait_for_session_update(session.pid)

    assert render(view) =~ "My notebook"
  end
end
```

The pattern: send an update directly to the GenServer, wait for it to propagate,
then re-render the view and assert.

### 10e. Confirmation dialogs

**File**: `test/livebook_web/live/home_live_test.exs` (lines 102-120)

```elixir
test "allows closing session after confirmation", %{conn: conn} do
  {:ok, %{id: id} = session} = Sessions.create_session()
  {:ok, view, _} = live(conn, ~p"/")

  view
  |> element(~s{[data-test-session-id="#{session.id}"] button}, "Close")
  |> render_click()

  Sessions.subscribe()
  render_confirm(view)  # Uses Livebook.TestHelpers.render_confirm/2

  assert_receive {:session_closed, %{id: ^id}}
end
```

`render_confirm` is a custom helper in `TestHelpers`:

**File**: `test/support/test_helpers.ex` (lines 64-73)

```elixir
def render_confirm(view, options \\ %{}) do
  options =
    for {option, value} <- options,
        into: %{},
        do: {Atom.to_string(option), Atom.to_string(value)}

  view
  |> element(~s/[data-el-confirm-form]/)
  |> render_submit(%{"options" => options})
end
```

### 10f. Form interactions

**File**: `test/livebook_web/live/settings_live_test.exs` (lines 16-39)

```elixir
test "adds an environment variable", %{conn: conn} do
  attrs = params_for(:env_var)

  {:ok, view, html} = live(conn, ~p"/settings/env-var/new")
  assert html =~ "Add environment variable"

  view
  |> element("#env-var-form")
  |> render_change(%{"env_var" => attrs})

  view
  |> element("#env-var-form")
  |> render_submit(%{"env_var" => attrs})

  assert_patch(view, ~p"/settings")
  assert render(view) =~ attrs.name
end
```

### 10g. Controller + LiveView hybrid tests

**File**: `test/livebook_web/controllers/session_controller_test.exs` (lines 346-361)

```elixir
test "given :wav input returns the audio binary", %{conn: conn, tmp_dir: tmp_dir} do
  {session, input_id} = start_session_with_audio_input(:wav, "wav content", tmp_dir)

  {:ok, view, _} = Phoenix.LiveViewTest.live(conn, ~p"/sessions/#{session.id}")

  token = LivebookWeb.SessionHelpers.generate_input_token(view.pid, input_id)

  conn = conn |> with_password_auth() |> get(~p"/public/sessions/audio-input/#{token}")

  assert conn.status == 200
  assert conn.resp_body == "wav content"
end
```

### 10h. `LazyHTML` for DOM queries

**File**: `test/livebook_web/live/app_session_live_test.exs` (lines 168-169)

```elixir
{:ok, view, _html} = live(conn, ~p"/apps/#{slug}")

html =
  view
  |> element("#session-#{session_id}", "")
  |> render()
  |> LazyHTML.from_fragment()
  |> LazyHTML.query(~s/[data-output-size="default"] [data-el-output]/)
```

Used for structured DOM assertions beyond simple string matching.

---

## Summary of Key Patterns

| Practice | Livebook Approach |
|----------|------------------|
| **Factory** | Custom `Livebook.Factory` with `build/1,2` and `params_for/2` |
| **HTTP stubbing** | `Bypass` (primary), `Req.Test` (inline) |
| **Mocks** | Protocol-based stubs (`NoopRuntime`), no Mox |
| **Async** | 54/54 modules use `async: true` by default |
| **Describe** | Extensive use of `describe` blocks in every test file |
| **Tags** | `@tag :tmp_dir`, `@moduletag`, `@tag authentication: %{...}` |
| **Property tests** | Not used |
| **Coverage** | Not tracked (no ExCoveralls) |
| **Test-only deps** | `bypass`, `lazy_html`, `pythonx`, `kino` |
| **LiveView** | `ConnCase` + `live/3`, `render_click/2`, `render_hook/3` |
| **Confirmation dialogs** | Custom `render_confirm/2` helper |
| **Session cleanup** | `on_exit` in `start_session` helper |
| **Runtime stubbing** | `NoopRuntime` for fast GenServer tests |
