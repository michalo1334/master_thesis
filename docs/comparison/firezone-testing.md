# Firezone Testing Practices

> Analysis of the Elixir test suite at `elixir/test/` (319 test files).

---

## 1. Test Structure

```
test/
├── test_helper.exs              # ExUnit bootstrap + DB connection debug
├── support/                     # Shared test modules
│   ├── case_template.ex         # SQL Sandbox injection mixin
│   ├── data_case.ex             # DB-access test case (DataCase)
│   ├── conn_case.ex             # PortalWeb HTTP/LiveView test case
│   ├── api_conn_case.ex         # PortalAPI HTTP test case
│   ├── channel_case.ex          # PortalAPI WebSocket/Channel test case
│   ├── assertions.ex            # `wait_for` polling assertion helper
│   ├── outbound_email_helpers.ex# Oban-based email assertion helpers
│   ├── openid_connect_fixtures.ex # Req.Test-based OIDC mock server
│   ├── fixture.ex               # Base fixture macro + unique-id generators
│   ├── fixtures/                # ~25 domain-specific fixture modules
│   ├── mocks/                   # Req.Test-based HTTP mock helpers
│   └── mailer/                  # Custom Swoosh test adapter
├── portal/                      # Unit / integration tests for Portal context
├── portal_api/                  # REST API controller + Channel tests
│   ├── controllers/             # REST controller tests
│   ├── client/                  # Client WebSocket channel + views
│   ├── gateway/                 # Gateway WebSocket channel + views
│   ├── relay/                   # Relay WebSocket channel
│   ├── plugs/                   # Plug tests
│   └── sockets/                 # Socket-level tests
├── portal_web/                  # PortalWeb (Phoenix) tests
│   ├── controllers/             # Web controller tests
│   ├── live/                    # LiveView tests
│   ├── live_hooks/              # LiveView hook tests
│   ├── plugs/                   # Web plug tests
│   ├── components/              # Component tests
│   └── cookie/                  # Signed cookie tests
├── portal_ops/                  # Operations endpoint tests
├── openid_connect/              # OIDC library tests (vendored)
├── credo/                       # Custom Credo check tests
└── fixtures/                    # HTTP response fixtures (real provider data)
    ├── http/
    │   ├── google/              # Real Google OIDC discovery/JWKS
    │   ├── azure/
    │   ├── okta/
    │   ├── auth0/
    │   ├── keycloak/
    │   ├── onelogin/
    │   ├── cognito/
    │   └── vault/
    └── jwks/
```

**Key pattern**: The directory tree mirrors `lib/` — one top-level directory per context (`portal/`, `portal_api/`, `portal_web/`). Each controller or LiveView in `lib/` has a matching test file in the same relative path.

---

## 2. Test Types

### 2a. Unit Tests (`use ExUnit.Case, async: true`)

Pure logic tests that don't touch the DB or HTTP. Used for schema helpers, type casts, validators, etc.

**File**: `test/portal/schema_helpers_test.exs` (line 2)
```elixir
defmodule Portal.SchemaHelpersTest do
  use ExUnit.Case, async: true
  # ...
end
```

### 2b. Database Tests (`use Portal.DataCase`)

Tests that read/write to the DB via Ecto. The SQL Sandbox wraps each test in a transaction.

**File**: `test/support/data_case.ex` (lines 16-30)
```elixir
defmodule Portal.DataCase do
  use ExUnit.CaseTemplate
  use Portal.CaseTemplate

  using do
    quote do
      import Ecto
      import Ecto.Changeset
      import Swoosh.TestAssertions
      import Portal.DataCase

      alias Portal.Repo
      alias Portal.Fixtures
      alias Portal.Mocks
    end
  end
end
```

### 2c. Controller Tests (`use PortalAPI.ConnCase`)

REST API controller tests using `Phoenix.ConnTest`. Tests exercise real HTTP endpoints with router pipelines.

**File**: `test/portal_api/controllers/actor_controller_test.exs` (lines 1-3)
```elixir
defmodule PortalAPI.ActorControllerTest do
  use PortalAPI.ConnCase, async: true

  setup do
    account = account_fixture()
    actor = actor_fixture(type: :api_client, account: account)
    %{account: account, actor: actor}
  end

  describe "index/2" do
    test "lists all actors", %{conn: conn, account: account, actor: actor} do
      conn = conn
        |> authorize_conn(actor)
        |> put_req_header("content-type", "application/json")
        |> get("/actors")

      assert %{"data" => data} = json_response(conn, 200)
    end
  end
end
```

### 2d. PortalWeb ConnCase (`use PortalWeb.ConnCase`)

PortalWeb tests — a Phoenix-idiomatic ConnCase that also provides helpers for LiveView testing, HTML table parsing, form validation assertions, and authentication cookie setup.

**File**: `test/portal_web/live/sign_in_test.exs` (lines 1-2)
```elixir
defmodule PortalWeb.SignInTest do
  use PortalWeb.ConnCase, async: true

  test "renders sign-in page with account name", %{conn: conn, account: account} do
    {:ok, _lv, html} = live(conn, ~p"/#{account}/sign_in")
    assert html =~ "Sign in to #{account.name}"
  end
end
```

### 2e. Channel Tests (`use PortalAPI.ChannelCase`)

WebSocket/Channel tests for the `PortalAPI` — client, gateway, and relay channels. These are the most complex tests in the suite (e.g., `channel_test.exs` for the client channel is ~7500 lines).

**File**: `test/portal_api/client/channel_test.exs` (lines 1-4)
```elixir
defmodule PortalAPI.Client.ChannelTest do
  use PortalAPI.ChannelCase, async: true

  defp join_channel(client, subject, opts \\ []) do
    # builds socket, subscribes, joins the channel
  end
end
```

### 2f. Plug Tests

Standalone plug tests that test middleware in isolation.

**File**: `test/portal_api/plugs/validate_uuid_params_test.exs`

---

## 3. Factories / Fixtures

**No ExMachina.** Firezone uses a hand-rolled fixture system with dedicated modules per domain entity.

### Base fixture (`test/support/fixture.ex`)

Provides `unique_integer`, `unique_ipv4`, `unique_ipv6`, `unique_public_key`, and `pop_assoc_fixture` helpers using `System.unique_integer` (not sequences or Ecto auto-increment).

**File**: `test/support/fixture.ex` (lines 42-49)
```elixir
def unique_integer do
  System.unique_integer([:positive, :monotonic])
end

def unique_ipv4 do
  number = unique_integer()
  <<a::size(8), b::size(8), c::size(8), d::size(8)>> = <<number::32>>
  {a, b, c, d}
end
```

### Domain-specific fixtures

Each domain entity gets a `*Fixtures` module. Every module follows a consistent pattern:

1. `valid_*_attrs/1` — returns a map of valid attributes with unique values
2. `*_fixture/1` — creates and persists the entity, accepting overrides

**File**: `test/support/fixtures/account_fixtures.ex` (lines 12-66)
```elixir
defmodule Portal.AccountFixtures do
  def valid_account_attrs(attrs \\ %{}) do
    unique_num = System.unique_integer([:positive, :monotonic])
    Enum.into(attrs, %{
      name: "Account #{unique_num}",
      slug: "account_#{unique_num}",
      key: Portal.Account.new_key(),
      config: %{...},
      features: %{...},
      limits: %{...},
      metadata: %{stripe: %{}}
    })
  end

  def account_fixture(attrs \\ %{}) do
    attrs = valid_account_attrs(attrs)
    %Portal.Account{}
    |> cast(attrs, [:name, :legal_name, :slug, :key])
    |> cast_embed(:config)
    |> cast_embed(:features)
    |> cast_embed(:limits)
    |> Repo.insert!()
  end
end
```

**File**: `test/support/fixtures/actor_fixtures.ex` (lines 12-72)
```elixir
defmodule Portal.ActorFixtures do
  def valid_actor_attrs(attrs \\ %{}) do
    unique_num = System.unique_integer([:positive, :monotonic])
    first_name = Enum.random(~w[Wade Dave Seth ...])
    last_name = Enum.random(~w[Robyn Traci Desiree ...])
    type = Map.get(attrs, :type, :account_user)
    base_attrs = %{name: "#{first_name} #{last_name} #{unique_num}", type: type}
    # email added conditionally based on type
  end

  def actor_fixture(attrs \\ %{}) do
    # resolves account from attrs or creates one
    # casts and inserts via Repo
  end

  def admin_actor_fixture(attrs), do: actor_fixture(Map.put(attrs, :type, :account_admin_user))
  def service_account_fixture(attrs), ...
  def api_client_fixture(attrs), ...
end
```

**All fixture modules** (25 total):

| Module | Purpose |
|--------|---------|
| `AccountFixtures` | Accounts with plans (starter/team/enterprise) |
| `ActorFixtures` | Users, admins, service accounts, API clients |
| `AuthProviderFixtures` | Auth providers (email, OIDC, Google, Okta, Entra) |
| `BannerFixtures` | Announcement banners |
| `ChangeLogFixtures` | Change log entries |
| `ClientSessionFixtures` | Client sessions |
| `DeviceFixtures` | Devices (with public key generation) |
| `DirectoryFixtures` | Directory connectors |
| `FeaturesFixtures` | Feature flags |
| `FlowLogFixtures` | Flow logs |
| `GatewaySessionFixtures` | Gateway sessions |
| `GroupFixtures` | Groups |
| `IdentityFixtures` | Identities |
| `LogSinkFixtures` | Log sink configurations |
| `MembershipFixtures` | Actor-group memberships |
| `ObanJobFixtures` | Oban job factories |
| `OktaDirectoryFixtures` | Okta-specific directory data |
| `OutboundEmailFixtures` | Outbound email records |
| `PolicyFixtures` | Access policies |
| `PolicyAuthorizationFixtures` | Policy authorization records |
| `PortalSessionFixtures` | Portal sessions |
| `RelayFixtures` | Relays |
| `ResourceFixtures` | Resources (DNS, CIDR, IP, internet) |
| `SessionLogFixtures` | Session logs |
| `SiteFixtures` | Sites |
| `SubjectFixtures` | Authentication subjects (actor + session + context) |
| `TokenFixtures` | API tokens and client tokens |
| `TrustAnchorFixtures` | X.509 trust anchors (+ PEM/DER cert fixtures) |

---

## 4. Mocks

**No Mox.** Firezone uses `Req.Test` (the built-in HTTP stub from the `req` library) to mock all external HTTP APIs. The approach is:

1. **Test config** wires `Req.Test` as a plug into every HTTP client's `req_opts` (config/test.exs).
2. **Mock modules** in `test/support/mocks/` provide convenience functions to set up stubs.
3. **Process dictionary** stores per-test state for dynamic responses.

### Configuration pattern (`config/test.exs`, lines 98-109)

```elixir
config :portal, Portal.Billing.Stripe.APIClient,
  endpoint: "https://api.stripe.com",
  req_opts: [
    plug: {Req.Test, Portal.Billing.Stripe.APIClient},
    retry: false
  ]

config :portal, Portal.Okta.APIClient,
  req_opts: [
    plug: {Req.Test, Portal.Okta.APIClient},
    retry: false
  ]
```

This is done for **10+ external API clients**: Stripe, Okta, Splunk, Datadog, NewRelic, Elastic, Sentinel, S3, QRadar, Azure, Entra, Google, ComponentVersions, and a generic HTTP client.

### Mock module example — Stripe (`test/support/mocks/stripe.ex`, lines 22-43)

```elixir
defmodule Portal.Mocks.Stripe do
  def stub(expectations) when is_list(expectations) do
    Req.Test.stub(APIClient, fn conn ->
      method = conn.method
      path = "/" <> Enum.join(conn.path_info, "/")

      case find_expectation(expectations, method, path) do
        {:ok, {status, response}} ->
          conn |> put_resp_content_type("application/json") |> send_resp(status, JSON.encode!(response))
        :not_found ->
          conn |> put_resp_content_type("application/json") |> send_resp(404, ...)
      end
    end)
  end
end
```

### Process-isolated OIDC mocks (`test/support/mocks/oidc.ex`, lines 33-48)

Each test gets a unique endpoint suffix to prevent cache collisions in parallel runs:

```elixir
def mock_endpoint do
  suffix = case Process.get({__MODULE__, :mock_endpoint_suffix}) do
    nil -> suffix = System.unique_integer([:positive, :monotonic])
           Process.put({__MODULE__, :mock_endpoint_suffix}, suffix)
           suffix
    suffix -> suffix
  end
  "#{@mock_endpoint_base}/#{suffix}"
end
```

### Custom adapters — Mailer (`test/support/mailer/mailer_test_adapter.ex`)

```elixir
defmodule Portal.Mailer.TestAdapter do
  use Swoosh.Adapter

  def deliver(email, config) do
    Swoosh.Adapters.Local.deliver(email, config)
    Swoosh.Adapters.Test.deliver(email, config)
  end
end
```

Dual-delivery: writes to both the local in-memory store (`Swoosh.Adapters.Test` for assertions with `Swoosh.TestAssertions`) and the filesystem (`Swoosh.Adapters.Local` for preview).

---

## 5. Test Configuration

### `test/test_helper.exs` (lines 1-23)

```elixir
Ecto.Adapters.SQL.Sandbox.mode(Portal.Repo, :manual)
:ok = Ecto.Adapters.SQL.Sandbox.checkout(Portal.Repo)

# Debug: log active connections to detect "too many clients" errors
db_name = Portal.Repo.config()[:database]
query = "SELECT count(*) FROM pg_stat_activity WHERE datname = $1"
case Ecto.Adapters.SQL.query(Portal.Repo, query, [db_name], log: false) do
  {:ok, %{rows: [[count]]}} ->
    IO.puts("--- Active connections to #{db_name}: #{count} (Limit is usually 100) ---")
end

Ecto.Adapters.SQL.Sandbox.checkin(Portal.Repo)
ExUnit.start(formatters: [ExUnit.CLIFormatter, JUnitFormatter])
```

### SQL Sandbox injection — `Portal.CaseTemplate` (`test/support/case_template.ex`)

A shared `__using__` macro that all three case templates (DataCase, ConnCase, ChannelCase) reference:

```elixir
defmacro __using__(_opts) do
  quote do
    setup tags do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Portal.Repo)
      unless tags[:async] do
        Ecto.Adapters.SQL.Sandbox.mode(Portal.Repo, {:shared, self()})
      end
      :ok
    end
  end
end
```

Key behavior:
- All DB tests check out the sandbox in setup.
- **Async tests** (`async: true`) use the default `:manual` mode — each test gets its own connection.
- **Sync tests** (`async: false`) use `{:shared, self()}` to share the connection — the test process acts as the owner.

### `config/test.exs` highlights (344 lines)

- **Partitioned DB names**: `firezone_test` + `_p#{MIX_TEST_PARTITION}` (line 7-12)
- **8 repos** all point to same test DB with `pool: Ecto.Adapters.SQL.Sandbox` (lines 32-45)
- **Oban**: `testing: :manual` mode, no cron jobs (lines 49-70, 248)
- **Rate limiters disabled** for general tests: `refill_rate: 100_000, capacity: 1_000_000` (lines 264-273)
- **Endpoints on ephemeral ports**: `port: 0` with `server: true` (lines 256-258, 290-300)
- **Argon2**: reduced cost for speed: `t_cost: 1, m_cost: 8` (line 317)
- **Geolix**: fake adapter with empty data (lines 319-322)
- **Logger**: `level: :info` for assertion capability
- **Capture log**: `capture_log: true` in ExUnit config

### `mix.exs` test configuration (lines 20-23)

```elixir
elixirc_paths: elixirc_paths(Mix.env()),
test_coverage: [tool: ExCoveralls],
test_ignore_filters: [~r"^test/fixtures/"],
```

- `test/support/` is compiled in `:test` env only (line 55)
- `test/fixtures/` is ignored from test discovery (they are data files, not test modules)

---

## 6. Property-Based Testing

**Not used.** There is no `:stream_data` dependency in `mix.exs`, no `ExUnitProperties` usage, and no property-based tests anywhere.

---

## 7. Code Coverage

### ExCoveralls configuration (`coveralls.json`)

```json
{
  "skip_files": ["test"]
}
```

Minimal — just skips the test directory. No `:preferred_envs` config in `mix.exs` ensures coveralls uses `:test` env.

### `mix.exs` (lines 5-11)

```elixir
def cli do
  [
    preferred_envs: [
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  ]
end
```

Supported reporters: CLI summary, detailed, HTML, and POST (for CI upload).

---

## 8. Async Test Usage

**Overwhelmingly `async: true`**. The majority of test files use `async: true`, including all controller tests, all LiveView tests, and nearly all DB tests.

### `async: false` — only 2 files

Only two test files in the entire suite opt out:

| File | Reason |
|------|--------|
| `test/portal_web/rate_limit_test.exs` | Tests shared IP-based rate limiting — parallel runs would interfere |
| `test/portal/telemetry_toggle_test.exs` | Race conditions on handler state (noted in a comment, line 4) |

### How async works with the DB sandbox

The `Portal.CaseTemplate` (`test/support/case_template.ex`) handles both cases:

```elixir
setup tags do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Portal.Repo)
  unless tags[:async] do
    Ecto.Adapters.SQL.Sandbox.mode(Portal.Repo, {:shared, self()})
  end
end
```

- **Async tests**: each runs in its own process with its own sandbox check-out. Postgres' row-level locking + MVCC prevents conflicts.
- **Sync tests**: share the connection via `{:shared, self()}`, which is necessary for tests that manipulate shared state (rate limit buckets, telemetry handlers).

---

## 9. E2E Tests

**No browser-based E2E tests exist** in the Elixir project. There are no Playwright, Cypress, Wallaby, or Hound test files. The Elixir test suite is purely backend integration/unit tests.

LiveView tests (`PortalWeb.ConnCase` + `Phoenix.LiveViewTest`) are the closest thing to "browser-like" testing, using the LiveView test DSL to mount and interact with LiveViews programmatically:

```elixir
test "renders sign-in page with account name", %{conn: conn, account: account} do
  {:ok, _lv, html} = live(conn, ~p"/#{account}/sign_in")
  assert html =~ "Sign in to #{account.name}"
end
```

---

## 10. Test Support Modules

### Summary of `test/support/`

| File | Purpose |
|------|---------|
| `case_template.ex` | SQL Sandbox checkout injector (24 lines) |
| `data_case.ex` | DB test case: imports `Ecto`, `Ecto.Changeset`, `Swoosh.TestAssertions`, aliases `Repo`, `Fixtures`, `Mocks` |
| `conn_case.ex` | PortalWeb test case: builds conn with geo headers, auth helpers, LiveView HTML/table helpers (366 lines) |
| `api_conn_case.ex` | PortalAPI test case: builds conn with Bearer token auth helpers (51 lines) |
| `channel_case.ex` | PortalAPI channel test case: builds socket `connect_info`, isolates PG scope & relay presence per test (108 lines) |
| `assertions.ex` | `wait_for/2` — polling assertion helper with timeout (31 lines) |
| `outbound_email_helpers.ex` | Queries Oban jobs to assert on queued emails (46 lines) |
| `openid_connect_fixtures.ex` | Req.Test-based OIDC mock server fixture (186 lines) |
| `fixture.ex` | Base fixture macro + `unique_*` generators (65 lines) |
| `fixtures/*.ex` | 25 domain-specific fixture modules |
| `mocks/*.ex` | 4 HTTP mock modules (Stripe, OIDC, FirezoneWebsite, OktaDirectory) |
| `mailer/mailer_test_adapter.ex` | Dual-delivery Swoosh adapter (Test + Local) |

### ConnCase authentication helpers (`test/support/conn_case.ex`)

The `authorize_conn` function (line 79-87) demonstrates how PortalWeb tests set up authentication:

```elixir
def authorize_conn(conn, %Portal.Actor{} = actor) do
  account = Portal.Repo.get!(Portal.Account, actor.account_id)
  auth_provider = Portal.AuthProviderFixtures.email_otp_provider_fixture(account: account)
  authorize_conn_with_provider(conn, actor, auth_provider)
end

def authorize_conn_with_provider(conn, actor, provider) do
  context = %Portal.Authentication.Context{...}
  {:ok, session} = Portal.Authentication.create_portal_session(actor, provider.id, context, expires_at)
  {:ok, subject} = Portal.Authentication.build_subject(session, context)
  cookie = %PortalWeb.Cookie.Session{session_id: session.id}
  conn = PortalWeb.Cookie.Session.put(conn, actor.account_id, cookie)
  # ... transfer cookie from response to request
end
```

### ChannelCase connection info (`test/support/channel_case.ex`)

Rate-limiting isolation in channel tests uses unique random IPs per test:

```elixir
def unique_ip do
  {:rand.uniform(255), :rand.uniform(255), :rand.uniform(255), :rand.uniform(255)}
end

def build_connect_info(opts \\ []) do
  ip = Keyword.get(opts, :ip, unique_ip())
  # ...
  %{
    user_agent: user_agent,
    peer_data: %{address: ip},
    x_headers: x_headers,
    trace_context_headers: []
  }
end
```

### Insta-specced HTTP fixtures (`test/fixtures/http/`)

Real provider responses checked into `test/fixtures/http/{provider}/discovery_document.exs`. Each file is a plain Elixir map:

```elixir
# test/fixtures/http/google/discovery_document.exs
%{
  status_code: 200,
  body: %{
    "authorization_endpoint" => "https://accounts.google.com/o/oauth2/v2/auth",
    "issuer" => "https://accounts.google.com",
    "jwks_uri" => "https://www.googleapis.com/oauth2/v3/certs",
    "token_endpoint" => "https://oauth2.googleapis.com/token",
    "userinfo_endpoint" => "https://openidconnect.googleapis.com/v1/userinfo"
  },
  headers: [
    {"Content-Type", "application/json"},
    {"Cache-Control", "public, max-age=3600"}
  ]
}
```

---

## Key Takeaways

| Practice | Firezone approach |
|----------|-------------------|
| **Test framework** | ExUnit with `describe`/`test` blocks |
| **Fixtures** | Hand-rolled per-domain modules (`*Fixtures`), no ExMachina |
| **Mocks** | `Req.Test` stub-based, no Mox |
| **Email testing** | Custom `Swoosh.Adapter` (Test + Local) + Swoosh.TestAssertions |
| **Background jobs** | Oban `:manual` mode, flush queues explicitly in tests |
| **Property-based** | Not used |
| **Coverage** | ExCoveralls (CLI, HTML, POST) |
| **Async** | Nearly all tests `async: true`; only 2 files opt out |
| **E2E** | None (no browser tests) |
| **DB isolation** | Ecto SQL Sandbox with `manual` mode for async, `{:shared, self()}` for sync |
| **Test data isolation** | `System.unique_integer` for IDs; unique IPs per socket test; per-test OIDC endpoints |
| **Test compilation** | `test/support/` compiled only in `:test` env |
| **CI output** | ExUnit.CLIFormatter + JUnitFormatter |
