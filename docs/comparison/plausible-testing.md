# Plausible Testing Practices

Exploration of the test suite in [Plausible Analytics](https://github.com/plausible/analytics) (Elixir/Phoenix app).

---

## 1. Test Directory Structure

```
test/
  test_helper.exs
  support/            # Shared modules, case templates, mocks, factories
    data_case.ex
    conn_case.ex
    plugins_api_case.ex
    factory.ex          # ExMachina factory definitions
    test_utils.ex       # ~387 lines of helpers
    html.ex             # LazyHTML-based DOM assertions
    assert_matches.ex   # ~406 lines custom pattern-match macro
    sandbox.ex          # Sandbox helper for background processes
    sentry.ex           # Sentry test mode setup
    http_mocker.ex      # JSON-fixture-driven HTTP mock (replaces ExVCR)
    exchange_rate_mock.ex
    google_api_mock.ex
    test_paddle_api_mock.ex
    dns.ex              # DNS mock helpers (Mox-based)
    dns_server.ex       # Real UDP DNS server for tests
    teams/
      test.ex           # ~466 lines: new_user/1, new_site/1, subscription helpers
    audit/
      test_schema.ex
    dev/                # Dev-only mocks (billing, controllers, etc.)
      billing/
        dev_paddle_api_mock.ex
      controllers/
      templates/
      views/
  plausible/            # Unit & integration tests for core domain logic
    auth/
    billing/
    session/
    imported/
    ingestion/
    ...
  plausible_web/        # Controller, LiveView, component tests
    controllers/
      api/
        internal_controller/
        external_stats_controller/
        ...
    live/
      components/
    views/
  workers/              # Oban worker tests (21 files)
  e2e/                  # Elixir-side E2E test helpers (in same dir as E2E above)
  load/                 # Load testing scripts
  priv/                 # Test fixtures (GeoLite2 test DB)
e2e/                    # Playwright-based E2E tests (Node.js)
  tests/
    dashboard/
    test-utils.ts
    fixtures.ts
  playwright.config.ts
```

---

## 2. Test Types by Location

| Layer | Directory | Type | Description |
|-------|-----------|------|-------------|
| Unit | `test/plausible/` | `ExUnit.Case` or `Plausible.DataCase` | Core domain logic, no HTTP |
| Controller | `test/plausible_web/controllers/` | `PlausibleWeb.ConnCase` | Request/response, HTML, JSON |
| LiveView | `test/plausible_web/live/` | `PlausibleWeb.ConnCase` + `Phoenix.LiveViewTest` | LiveView interaction |
| Worker | `test/workers/` | `Plausible.DataCase` | Oban job execution |
| Component | `test/plausible_web/live/components/` | `PlausibleWeb.ConnCase` | LiveView component tests |
| E2E | `e2e/tests/` | Playwright | Full browser automation |

### Example: Unit test (no DB)

```elixir
# test/plausible/plausible_test.exs:1-15
defmodule PlausibleTest do
  use ExUnit.Case, async: true

  describe "product_name/0" do
    @tag :ce_build_only
    test "returns the correct name in CE" do
      assert Plausible.product_name() == "Plausible CE"
    end
  end
end
```

### Example: Controller test

```elixir
# test/plausible_web/controllers/stats_controller_test.exs:8-15
describe "GET /:domain - anonymous user" do
  test "public site - shows site stats", %{conn: conn} do
    site = new_site(public: true)
    populate_stats(site, [build(:pageview)])
    conn = get(conn, "/#{site.domain}")
    resp = html_response(conn, 200)
    assert element_exists?(resp, @react_container)
  end
end
```

### Example: LiveView test

```elixir
# test/plausible_web/live/sites_test.exs:2-15
defmodule PlausibleWeb.Live.SitesTest do
  use PlausibleWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  setup [:create_user, :log_in]

  describe "/sites" do
    test "renders empty sites page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, "/sites")
      assert text(html) =~ "My personal sites"
    end
  end
end
```

---

## 3. ExMachina Factories

**File:** `test/support/factory.ex` (415 lines)

They use `ExMachina.Ecto` with `repo: Plausible.Repo`. Factories are imported automatically via `DataCase` and `ConnCase`.

### Schema: Factory functions

Pattern: `def <name>_factory(attrs \\ [])` and `merge_attributes(struct, attrs)`.

```elixir
# test/support/factory.ex:54-65
def user_factory(attrs) do
  pw = Map.get(attrs, :password, "password")
  user = %Plausible.Auth.User{
    name: "Jane Smith",
    email: sequence(:email, &"email-#{&1}@example.com"),
    password_hash: Plausible.Auth.Password.hash(pw),
    email_verified: true
  }
  merge_attributes(user, attrs)
end
```

```elixir
# test/support/factory.ex:81-92
def site_factory(attrs) do
  domain = sequence(:domain, &"é-#{&1}.example.com")  # Unicode in domain!
  site = %Plausible.Site{
    native_stats_start_at: ~N[2000-01-01 00:00:00],
    domain: domain,
    timezone: "Etc/UTC"
  }
  merge_attributes(site, attrs)
end
```

```elixir
# test/support/factory.ex:126-128
def pageview_factory(attrs) do
  Map.put(event_factory(attrs), :name, "pageview")
end
```

```elixir
# test/support/factory.ex:155-181  (complex factory with branching)
def goal_factory(attrs) do
  display_name_provided? = Map.has_key?(attrs, :display_name)
  attrs = case {attrs, display_name_provided?} do
    {%{page_path: path}, false} when is_binary(path) ->
      Map.put(attrs, :display_name, "Visit " <> path)
    ...
  end
  merge_attributes(%Plausible.Goal{}, attrs)
end
```

### Usage in tests

```elixir
# Direct insert
insert(:segment, site: site, owner: user, type: :site, name: "EMEA region")
insert(:shared_link, site: site, password_hash: Plausible.Auth.Password.hash("password"))

# Build (not persisted)
build(:pageview, timestamp: timestamp)
build(:event, name: "pageview")

# Associations
build(:team_membership, team: team, user: user, role: :guest)
```

### Named sub-factories

```elixir
# test/support/factory.ex:197-207
def starter_subscription_factory do
  build(:subscription, paddle_plan_id: "910413")
end

def growth_subscription_factory do
  build(:subscription, paddle_plan_id: "857097")
end
```

---

## 4. Mocks: Mox + Custom Stubs

### Mox setup

Defined in `test/test_helper.exs`:

```elixir
# test/test_helper.exs:8-12
Mox.defmock(Plausible.HTTPClient.Mock, for: Plausible.HTTPClient.Interface)
Mox.defmock(Plausible.DnsLookup.Mock, for: Plausible.DnsLookupInterface)
```

Configured in `config/test.exs`:

```elixir
# config/test.exs:27-30
config :plausible, http_impl: Plausible.HTTPClient.Mock
config :plausible, dns_lookup_impl: Plausible.DnsLookup.Mock
```

### Mox: `expect` in tests

```elixir
# test/plausible/imported/google_analytics4_test.exs:61-65
expect(Plausible.HTTPClient.Mock, :post, fn "https://www.googleapis.com/oauth2/v4/token",
    _headers, _body, _opts ->
  {:ok, %Finch.Response{status: 200, headers: [], body: ~s|{"access_token": "abc"}|}}
end)
```

### Mox: `stub` in DNS helper module

```elixir
# test/support/dns.ex:9-14
def stub_dns do
  stub(Plausible.DnsLookup.Mock, :lookup, fn _domain, :in, type, _opts, _timeout ->
    case type do
      :a -> [{93, 184, 216, 34}]
      :aaaa -> []
    end
  end)
end
```

### Module-based stubs (not Mox)

Several mock modules implement behaviours directly, swapped via Application config:

**`Plausible.Google.API.Mock`** — Uses query filter values (e.g., `event:page` filter) as a hack to return different mock responses:

```elixir
# test/support/google_api_mock.ex:10-43
def fetch_stats(_auth, query, _pagination, _search) do
  case page_filter_value(query) do
    ["/empty"] -> {:ok, []}
    ["/unsupported-filters"] -> {:error, :unsupported_filters}
    _ -> {:ok, [%{name: "simple web analytics", visitors: 25, ...}]}
  end
end
```

**`Plausible.ExchangeRateMock`** — Implements `Money.ExchangeRates` behaviour:

```elixir
# test/support/exchange_rate_mock.ex:13-15
def get_latest_rates(_config) do
  {:ok, %{BRL: Decimal.new("0.7"), EUR: Decimal.new("1.2"), USD: Decimal.new(1)}}
end
```

### `Req.Test` inline plugs

For HTTP requests made through the `Req` library, they use `Req.Test.stub/2` directly in tests:

```elixir
# test/plausible/ssrf_test.exs:72-78
Req.Test.stub(__MODULE__, fn conn ->
  assert {"host", "93.184.216.34"} in conn.req_headers
  Plug.Conn.send_resp(conn, 200, "ok")
end)

assert {:ok, %Req.Response{status: 200, body: "ok"}} =
         SSRF.get("http://93.184.216.34/", plug: {Req.Test, __MODULE__})
```

---

## 5. The `double` Library

Used sparingly — only **one occurrence** found:

```elixir
# test/support/test_utils.ex:326-350
def monthly_pageview_usage_stub(penultimate_usage, last_usage) do
  Plausible.Teams.Billing
  |> Double.stub(:monthly_pageview_usage, fn _user ->
    %{
      last_cycle: %{...},
      penultimate_cycle: %{...}
    }
  end)
end
```

`Double.stub/3` temporarily stubs a function on a module for the test process. Listed in `mix.exs` as `{:double, "~> 0.8.0"}` — used in dev/test/ce_test/e2e_test.

---

## 6. Test Case Templates

Three case templates share similar setup patterns:

### DataCase (`test/support/data_case.ex`)

```elixir
# test/support/data_case.ex:17-43
using do
  quote do
    use Plausible.Repo
    use Plausible.TestUtils
    use Plausible
    use Plausible.Teams.Test
    import Plausible.Test.Support.HTML
    import Ecto.Changeset
    import Plausible.DataCase
    import Plausible.Factory
    import Plausible.AssertMatches
  end
end

setup tags do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Plausible.Repo)
  unless tags[:async] do
    Ecto.Adapters.SQL.Sandbox.mode(Plausible.Repo, {:shared, self()})
  end
  Plausible.Test.Support.Sandbox.allow_salts_process()
  :ok
end
```

### ConnCase (`test/support/conn_case.ex`)

Same setup + `build_conn()` + `prepare_conn()`.

```elixir
# test/support/conn_case.ex:37-47
setup tags do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Plausible.Repo)
  unless tags[:async] do
    Ecto.Adapters.SQL.Sandbox.mode(Plausible.Repo, {:shared, self()})
  end
  Plausible.Test.Support.Sandbox.allow_salts_process()
  conn = Phoenix.ConnTest.build_conn() |> Plausible.TestUtils.prepare_conn()
  {:ok, conn: conn}
end
```

### PluginsAPICase (`test/support/plugins_api_case.ex`)

For testing the Plugins API — creates a site and API token in setup.

### Key setup helpers (`Plausible.Teams.Test`)

```elixir
# test/support/teams/test.ex
def new_site(args \\ [])  # Creates site with team, optional owner
def new_user(args \\ [])   # Creates user with team
def team_of(user)          # Gets the owning team
def add_member(team, args) # Adds team member with role
def add_guest(site, args)  # Adds site guest
def subscribe_to_growth_plan(user)  # Factory-based subscription creation
def subscribe_to_enterprise_plan(user, attrs)
def set_current_team(conn, team)
```

### TestUtils (`test/support/test_utils.ex`)

Key helpers:

```elixir
def create_user(_)  # setup composable: {:ok, user: ...}
def create_site(%{user: user})
def log_in(%{user: user, conn: conn})
def populate_stats(site, events)  # Writes events to Clickhouse
def eventually(expectation, wait_time_ms \\ 50, retries \\ 10)  # Polling helper
def await_clickhouse_count(query, expected)  # Clickhouse eventual consistency
def random_ip()
def patch_env(env_key, value)  # Safe env patching with async guard
```

---

## 7. HTML Assertion Helpers

**`Plausible.Test.Support.HTML`** — LazyHTML-based DOM querying:

```elixir
# test/support/html.ex
def element_exists?(html, selector)     # Check DOM element exists
def find(html, selector)                # Find elements
def text_of_element(html, selector)     # Extract text content
def text_of_attr(resp, selector, attr)  # Extract attribute value
def submit_button(html, form)           # Find submit button
def form_exists?(html, action_path)
def elem_count(html, selector)
```

Uses the `LazyHTML` library to parse and query HTML fragments (faster than full parse).

### Custom `assert_matches` macro

**`Plausible.AssertMatches`** (406 lines) — A sophisticated macro that extends pattern matching with:

```elixir
# test/plausible_web/controllers/api/internal_controller/annotations_controller_test.exs:49-61
assert_matches [
                 ^strict_map(%{
                   "id" => ^any(:pos_integer),
                   "note" => "site note",
                   "type" => "site",
                   "datetime" => "2026-01-04",
                   "granularity" => "date",
                   "owner_id" => nil,
                   "owner_name" => nil,
                   "inserted_at" => ^any(:iso8601_naive_datetime),
                   "updated_at" => ^any(:iso8601_naive_datetime)
                 })
               ] = json_response(conn, 200)
```

Supported pin expressions:

- `^any(:integer)`, `^any(:string)`, `^any(:boolean)`, etc.
- `^any(:string, ~r/pattern/)` — type + regex
- `^any(:integer, &(&1 > 20))` — type + predicate
- `^~r/regex/` — shorthand regex
- `^exactly(%{foo: :bar})` — full equality check
- `^strict_map(%{...})` — verifies **all** map keys are enumerated
- `^function_name` — arbitrary boolean function

---

## 8. JSON-Fixture HTTP Mocking (replacing ExVCR)

**`Plausible.Test.Support.HTTPMocker`** (54 lines):

```elixir
# test/support/http_mocker.ex:13-22
def mock_http_with(http_mock_fixture) do
  mocks =
    "fixture/http_mocks/#{http_mock_fixture}"
    |> File.read!()
    |> Jason.decode!()
    |> Enum.into(%{}, &{{&1["url"], &1["request_body"]}, &1})

  stub(Plausible.HTTPClient.Mock, :post, fn url, _, params, _ ->
    http_mocker_stub(mocks, url, params)
  end)
end
```

JSON fixtures stored in `fixture/http_mocks/`:

```
fixture/http_mocks/
  google_auth#invalid_grant.json
  google_search_console.json
```

---

## 9. Code Coverage: ExCoveralls

```elixir
# mix.exs:16-18
test_coverage: [tool: ExCoveralls]
```

```elixir
# mix.exs:94
{:excoveralls, "~> 0.10", only: :test}
```

No custom coverage options (no `preferred`, `threshold`, or `ignore` directives visible).

---

## 10. Property-Based Testing

**Not used.** No StreamData dependency in `mix.exs`. No property-based test files found.

---

## 11. Tag System & Test Environments

### Environment aliases

```elixir
# mix.exs:55-56
"test.e2e": :e2e_test,
"test.e2e.ui": :e2e_test
```

### Environment-specific tagging

```elixir
# test/test_helper.exs:35-46
case Mix.env() do
  :ce_test ->
    ExUnit.configure(exclude: [:ee_only, :e2e | default_exclude])

  :e2e_test ->
    ExUnit.configure(exclude: [:test], include: [:e2e])

  _ ->
    ExUnit.configure(exclude: [:ce_build_only, :e2e | default_exclude])
end
```

### Tags used throughout:

| Tag | Purpose |
|-----|---------|
| `@tag :ee_only` | Enterprise Edition only |
| `@tag :ce_build_only` | Community Edition only (compiled but skipped in EE) |
| `@tag :slow` | Excluded by default |
| `@tag :minio` | Requires MinIO running |
| `@tag :migrations` | Excluded by default |
| `@describetag :ee_only` | Entire describe block EE-only |

---

## 12. Async & Test Isolation

### async: true usage

Async is **used inconsistently** — many tests are `async: false` even when they could be async.

```elixir
use PlausibleWeb.ConnCase, async: true     # Annotations controller test
use PlausibleWeb.ConnCase, async: true     # Sites LiveView test
use PlausibleWeb.ConnCase, async: false    # Stats controller test
use ExUnit.Case, async: true               # SSRF test (no DB)
```

### Sandbox mode per test:

```elixir
setup tags do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(Plausible.Repo)

  unless tags[:async] do
    Ecto.Adapters.SQL.Sandbox.mode(Plausible.Repo, {:shared, self()})
  end

  Plausible.Test.Support.Sandbox.allow_salts_process()
  ...
end
```

### Background process isolation

```elixir
# test/support/sandbox.ex
def allow_salts_process do
  case Process.whereis(Plausible.Session.Salts) do
    nil -> :ok
    pid -> Ecto.Adapters.SQL.Sandbox.allow(Plausible.Repo, self(), pid)
  end
end
```

### Safe env patching with async guard:

```elixir
# test/support/test_utils.ex:15-29
defmacro patch_env(env_key, value) do
  quote do
    if __MODULE__.__info__(:attributes)[:ex_unit_async] == [true] do
      raise "Patching env is unsafe in asynchronous tests."
    end
    original_env = Application.get_env(:plausible, unquote(env_key))
    Application.put_env(:plausible, unquote(env_key), unquote(value))
    on_exit(fn -> Application.put_env(:plausible, unquote(env_key), original_env) end)
  end
end
```

---

## 13. E2E Tests (Playwright)

### Setup

```
e2e/
  package.json
  playwright.config.ts
  tsconfig.json
  tests/
    dashboard/
      annotations.spec.ts
      behaviours.spec.ts
      breakdowns.spec.ts
      csv-export.spec.ts
      exploration.spec.ts
      filtering.spec.ts
      general.spec.ts
      main-graph.spec.ts
      segments.spec.ts
      team-setup.spec.ts
      top-stats.spec.ts
    fixtures.ts        # ~533 lines: register, login, addSite, populateStats, etc.
    test-utils.ts      # ~113 lines: expectLiveViewConnected, expectRows, etc.
```

### Configuration

```typescript
// e2e/playwright.config.ts
export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  retries: isCI ? 2 : 0,
  timeout: isCI ? 30_000 : 15_000,
  use: { baseURL, trace: 'on-first-retry' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    cwd: '..',
    command: 'mix phx.server',
    env: { MIX_ENV: 'e2e_test' },
    url: `${baseURL}/api/system/health/ready`,
    reuseExistingServer: !isCI
  }
})
```

### Key patterns

**Sequential flow via `test.step`:**

```typescript
// e2e/tests/dashboard/general.spec.ts:46-64
await test.step('public link', async () => {
  await page.goto(link, { waitUntil: 'commit' });
  await expect(page.getByTestId('site-switcher-static')).toContainText(domain);
  await expect(page.locator('#visitors')).toHaveText('1');
});
```

**Custom API for seeding data:**

```typescript
// e2e/tests/fixtures.ts:224-242
export async function populateStats({ request, domain, events }) {
  const response = await request.post('/e2e-tests/stats', {
    headers: { 'Content-Type': 'application/json' },
    data: { domain, events }
  });
  expect(response.ok()).toBeTruthy();
}
```

**Elixir controller backing E2E API routes** — routes like `/e2e-tests/stats`, `/e2e-tests/goal`, `/e2e-tests/funnel` are backend endpoints that insert test data directly.

### Running E2E tests

```bash
mix e2e.setup        # npm install + playwright install
mix test.e2e         # builds assets, migrates DB, starts server, runs Playwright
mix test.e2e --ui    # Playwright UI mode
```

---

## 14. Load & Worker Tests

### Load tests (`test/load/`)

Simple Node.js script for load testing — not a formal part of the test suite.

### Worker tests (`test/workers/`)

21 worker test files. They use `Plausible.DataCase` and trigger Oban jobs manually (Oban is configured `testing: :manual` in test config):

```elixir
# config/test.exs:38
config :plausible, Oban, testing: :manual
```

---

## 15. Key Patterns Summary

| Pattern | Implementation |
|---------|---------------|
| **Factories** | ExMachina with `merge_attributes/2`, `sequence/2`, `build`/`insert` |
| **Case templates** | `DataCase`, `ConnCase`, `PluginsAPICase` — all setup shared behavior |
| **Team/user onboarding** | `Plausible.Teams.Test` — centralized `new_user/1`, `new_site/1`, helpers |
| **Setup pipelines** | `setup [:create_user, :log_in, :create_site]` — composable setup |
| **Mocks** | Mox for HTTP + DNS, module-based stubs for Paddle/Google/ExchangeRate |
| **Inline HTTP mocks** | `Req.Test.stub/2` for Req-based HTTP calls |
| **JSON-fixture mocks** | `HTTPMocker` — reads JSON from `fixture/http_mocks/` |
| **DOM assertions** | Custom `element_exists?`, `text_of_attr`, `text_of_element` via LazyHTML |
| **Pattern-match assertions** | `assert_matches` with `^any()`, `^strict_map()`, `^~r/regex/` |
| **Environment tags** | `@tag :ee_only`, `@tag :ce_build_only` for edition-specific tests |
| **Clickhouse testing** | `populate_stats` writes events, `await_clickhouse_count` polls for eventual consistency |
| **E2E** | Playwright Chromium-only, parallel, with custom API for data seeding |
| **Coverage** | ExCoveralls, no custom thresholds |
| **Property-based** | Not used |
| **Double library** | Used once (`Double.stub`) for stubbing a billing module function |
