# Plausible Code Organization & Design Patterns

> Analyzed from `/tmp/comparison_repos/plausible` (Elixir/Phoenix, EE + CE dual build).

---

## 1. Module Structure

### Top-Level Layout

```
lib/
├── plausible/             # Business logic & domain contexts
├── plausible_web/         # Web layer (controllers, plugs, views, LiveViews)
├── workers/               # Oban background job workers
├── plausible.ex           # Build macros (`on_ee`, `on_ce`, `ee?`, `ce?`)
├── plausible_web.ex       # Web module macros
├── plausible_release.ex   # Release boot tasks
├── oban_error_reporter.ex # Telemetry handler for Oban errors
├── sentry_filter.ex       # Sentry event filter
└── mix/                   # Custom Mix tasks
```

### `lib/plausible/` — Main Subdirectories (67 entries)

| Directory/File | Purpose |
|---|---|
| `site.ex` / `sites.ex` | Site schema + Sites context |
| `teams.ex` / `teams/` | Teams context with 17 sub-modules (memberships, invitations, billing, policy, etc.) |
| `billing/` | Billing context (subscriptions, plans, Paddle API, features, quotas) |
| `auth/` | Auth context (user schema, API keys, TOTP, passwords, sessions) |
| `stats.ex` / `stats/` | Stats context (~50 modules: query builder, Clickhouse SQL, filters, imports, legacy) |
| `ingestion/` | Event ingestion pipeline (request parsing, validation, geolocation, persistor) |
| `session/` | Session tracking (balancer GenServer, cache store, write buffer, salts, transfer) |
| `shield/` | Shield rules (IP, country, page, hostname — each with cache) |
| `imported/` | Data import framework (~18 modules, importer behaviour pattern) |
| `data_migration/` | Clickhouse/Postgres versioned data migration support |
| `cache.ex` / `cache/` | Caching abstraction (adapter pattern, warmer processes) |
| `segments/` | Segments context |
| `annotations/` | Annotations context |
| `funnel/`, `goals/` | Funnel and goal schemas/contexts |
| `plugins/` | Plugins API modules |
| `google/` | Google API integration (GA4) |
| `audit/` | Audit logging (via `Plausible.Audit.Repo`) |

### `lib/plausible_web/` — Web Layer (19 entries)

```
controllers/          # 15 controller modules (auth, billing, settings, stats, API)
  api/                # Internal, external, public API controllers
  site/               # Site membership controller
live/                 # 33 LiveView modules
  components/         # Shared LiveView components
  plugins/            # Plugins API LiveViews
  shields/            # Shield settings LiveViews
  change_domain/      # Domain change LiveViews
plugs/                # 21 Plug modules
templates/            # Email & HTML templates
views/                # Phoenix views
```

### `lib/workers/` — Oban Workers (22 modules)

All workers live at the top-level `lib/workers/` directory and are named `Plausible.Workers.<Name>`:

```
schedule_email_reports.ex  send_email_report.ex    check_usage.ex
lock_sites.ex              rotate_salts.ex        import_analytics.ex
export_analytics.ex        purge_cdn_cache.ex     locations_sync.ex
traffic_change_notifier.ex send_trial_notifications.ex
... (22 total)
```

---

## 2. Phoenix Contexts

### Context Pattern

Plausible follows a **schema + context** pattern. Each domain has:

- A **schema module** (`Plausible.Site`, `Plausible.Teams.Team`, `Plausible.Goal`) — defines the Ecto schema, changesets, and business-logic functions directly on the struct.
- A **context module** (plural name: `Plausible.Sites`, `Plausible.Teams`, `Plausible.Goals`) — contains query and command functions, composing multiple schemas.

**Example — Sites context** (`lib/plausible/sites.ex`, line 1-10):
```elixir
defmodule Plausible.Sites do
  @moduledoc "Sites context functions."
  use Plausible
  import Ecto.Query
  alias Plausible.{Auth, Repo, Site, Teams, Billing}
  alias Plausible.Billing.Feature.SharedLinks
  alias Plausible.Site.SharedLink
```

### How Contexts Compose

Contexts freely reference each other — there is **no strict bounded context isolation**. For example, `Plausible.Sites.create/3` (`lib/plausible/sites.ex`, line 298) calls into:

- `Teams.get_or_create(user)` — another context
- `Teams.Billing.ensure_can_add_new_site(team)` — nested context
- `Billing.SiteLocker.update_for(team)` — billing context
- `Teams.start_trial(team)` — teams context

### Data Flow Pattern (Controller → Context → Repo)

Typical flow in `SiteController`:

```elixir
# lib/plausible_web/controllers/site_controller.ex (inferred pattern)
def create_site(conn, %{"site" => site_params}) do
  user = conn.assigns.current_user
  case Plausible.Sites.create(user, site_params) do
    {:ok, site} -> redirect(conn, to: "/#{site.domain}/settings")
    {:error, ...} -> render(conn, :new, changeset: ...)
  end
end
```

The context returns `{:ok, result}` or `{:error, reason}` tuples consistently. **No explicit service/action objects** — contexts are the service layer.

---

## 3. Schema Modules

### Standard Ecto Schema Pattern

Each schema uses `use Ecto.Schema`, `import Ecto.Changeset`, and defines changesets directly on the module.

**`Plausible.Site`** (`lib/plausible/site.ex`, lines 14-69):
```elixir
schema "sites" do
  field :domain, :string
  field :timezone, :string, default: "Etc/UTC"
  field :public, :boolean
  field :ingest_rate_limit_scale_seconds, :integer, default: 60
  embeds_one :imported_data, Plausible.Site.ImportedData, on_replace: :update
  belongs_to :team, Plausible.Teams.Team
  has_many :goals, Plausible.Goal, preload_order: [desc: :id]
  # Virtual fields for cache state
  field :from_cache?, :boolean, virtual: true, default: false
end
```

### Embedded Schemas

- `Plausible.Ingestion.Request` (`lib/plausible/ingestion/request.ex`, line 42-67): `@primary_key false` / `embedded_schema` — an embedded struct used as a DTO for event processing pipeline.

```elixir
@primary_key false
embedded_schema do
  field :remote_ip, :string
  field :user_agent, :string
  field :event_name, Plausible.Ecto.EventName
  field :uri, :map
  # ... more fields
end
```

### ClickHouse Schemas

Dual-database architecture: Postgres for relational data, ClickHouse for analytics.

```elixir
# lib/plausible/clickhouse_event_v2.ex
schema "events_v2" do
  field :name, Ch, type: "LowCardinality(String)"
  field :site_id, Ch, type: "UInt64"
  field :timestamp, :naive_datetime
  field :"meta.key", {:array, :string}
  # ...
end
```

```elixir
# lib/plausible/clickhouse_session_v2.ex
schema "sessions_v2" do
  field :sign, Ch, type: "Int8"  # CollapsingMergeTree sign
  field :is_bounce, BoolUInt8    # Custom Ecto.Type for boolean→UInt8
  field :session_id, Ch, type: "UInt64"
  # ...
end
```

### Schema-Embedded Business Logic

Schemas contain **domain logic functions** beyond just changesets — note `Site.tz_offset/2`, `Site.make_public/1`, `Goal.display_name/1` etc. This is a deliberate pattern where "fat models" co-exist with context modules.

### `on_ee` / `on_ce` Build-Time Conditional Fields

The `on_ee` macro conditionally compiles fields, changeset cast fields, and more:

```elixir
# lib/plausible/goal.ex, lines 13-31
on_ee do
  field :currency, Ecto.Enum, values: Money.Currency.known_current_currencies()
  many_to_many :funnels, Plausible.Funnel, join_through: Plausible.Funnel.Step
else
  field :currency, :string, virtual: true, default: nil
  field :funnels, {:array, :map}, virtual: true, default: []
end
```

---

## 4. Service / Action Objects

### No Dedicated Service Objects

Plausible does **not** use a formal service/action/command pattern (no `Service` suffix, no `lib/services/` directory). Context modules **are** the service layer.

### Pipeline Pattern in Ingestion

The event ingestion uses a **function pipeline** pattern (`lib/plausible/ingestion/event.ex`, lines 130-151):

```elixir
defp pipeline() do
  [
    drop_verification_agent: &drop_verification_agent/2,
    drop_datacenter_ip: &drop_datacenter_ip/2,
    drop_threat_ip: &drop_threat_ip/2,
    drop_shield_rule_hostname: &drop_shield_rule_hostname/2,
    drop_shield_rule_page: &drop_shield_rule_page/2,
    drop_shield_rule_ip: &drop_shield_rule_ip/2,
    put_geolocation: &put_geolocation/2,
    drop_shield_rule_country: &drop_shield_rule_country/2,
    put_user_agent: &put_user_agent/2,
    put_basic_info: &put_basic_info/2,
    put_source_info: &put_source_info/2,
    maybe_infer_medium: &maybe_infer_medium/2,
    put_props: &put_props/2,
    put_revenue: &put_revenue/2,
    put_salts: &put_salts/2,
    put_user_id: &put_user_id/2,
    validate_clickhouse_event: &validate_clickhouse_event/2,
    register_session: &register_session/2
  ]
end
```

Reduced via `Enum.reduce_while` with telemetry instrumentation around each step (line 153-161). Each step is a pure function receiving `%Plausible.Ingestion.Event{}` and returning either `:halt` (dropped) or `:cont` (continue).

### Importer Behaviour (Strategy Pattern)

`Plausible.Imported.Importer` (`lib/plausible/imported/importer.ex`, line 1-60) defines a **behaviour** with callbacks `name/0`, `parse_args/1`, `import_data/2`, `before_start/2`, `on_success/2`, `on_failure/1`:

```elixir
@callback name() :: atom()
@callback parse_args(map()) :: Keyword.t()
@callback import_data(Plausible.Imported.SiteImport.t(), Keyword.t()) ::
  :ok | {:ok, map()} | {:error, term()} | {:error, term(), Keyword.t()}
```

Implementations: `Plausible.Imported.UniversalAnalytics`, `Plausible.Imported.GoogleAnalytics4`, `Plausible.Imported.CSVImporter`, etc.

### Ecto.Multi for Transactions

Complex multi-step operations use `Ecto.Multi`. Example from `Plausible.Sites.create/3` (`lib/plausible/sites.ex`, lines 299-359):

```elixir
Ecto.Multi.new()
|> Ecto.Multi.put(:site_changeset, Site.new(params))
|> Ecto.Multi.run(:create_team, fn _repo, _context -> ... end)
|> Ecto.Multi.run(:ensure_can_add_new_site, fn _repo, %{create_team: team} -> ... end)
|> Ecto.Multi.run(:clear_changed_from, fn _repo, _context -> ... end)
|> Ecto.Multi.insert(:site, fn %{site_changeset: site, create_team: team} -> ... end)
|> Ecto.Multi.run(:trial, fn _repo, %{create_team: team} -> ... end)
|> Ecto.Multi.run(:updated_lock, fn _repo, %{create_team: team} -> ... end)
|> Repo.transaction()
```

---

## 5. Repository Pattern

### Multiple Ecto Repos

Plausible defines **5 Ecto repos** for different databases/roles:

| Repo | Adapter | Purpose |
|---|---|---|
| `Plausible.Repo` | `Ecto.Adapters.Postgres` | Primary relational store |
| `Plausible.ClickhouseRepo` | `Ecto.Adapters.ClickHouse` (read-only) | Analytics queries |
| `Plausible.IngestRepo` | Inferred (ClickHouse) | Event/session writes |
| `Plausible.AsyncInsertRepo` | Inferred (ClickHouse async) | Async ClickHouse inserts |
| `Plausible.ImportDeletionRepo` | Inferred (ClickHouse) | Import deletion operations |

### `Plausible.Repo` (`lib/plausible/repo.ex`)

Minimal — just sets adapter and imports `Plausible.Audit.Repo`:

```elixir
defmodule Plausible.Repo do
  use Ecto.Repo, otp_app: :plausible, adapter: Ecto.Adapters.Postgres
  use Plausible.Audit.Repo  # Adds audit logging via Repo hooks
end
```

### `Plausible.ClickhouseRepo` (`lib/plausible/clickhouse_repo.ex`)

Extends Ecto.Repo with custom `parallel_tasks/2` and query logging:

```elixir
def parallel_tasks(queries, opts \\ []) do
  ctx = OpenTelemetry.Ctx.get_current()
  Task.async_stream(queries, execute_with_tracing,
    max_concurrency: max_concurrency, timeout: task_timeout
  )
  |> Enum.to_list() |> Keyword.values()
end
```

### Data Migration Repos

For versioned data migrations targeting specific databases:

```
lib/plausible/data_migration/
├── clickhouse_repo.ex   # Clickhouse connection for migration use
├── postgres_repo.ex     # Postgres connection for migration use
```

### Cache Abstraction as Repository

`Plausible.Cache` (`lib/plausible/cache.ex`) provides a **`use`-based repository abstraction** over cached database lookups. Modules like `Plausible.Site.Cache` implement its callbacks and get automatic refresh logic.

---

## 6. Dependency Injection

### Configuration-Based DI

Dependencies are injected via `Application.get_env/3` at **multiple levels**:

1. **Backend selection** (`lib/plausible/ingestion/persistor.ex`, lines 15-17):
```elixir
defp backend(nil, user_id) do
  percent_enabled = :plausible
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:backend_percent_enabled)
  backend = :plausible
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:backend)
```

2. **Paddle API adapter** (`lib/plausible/billing/billing.ex`, line 164):
```elixir
def paddle_api() do
  Application.get_env(:plausible, :paddle)[:api_module] || Plausible.Billing.PaddleApi
end
```

3. **Finch pool configuration** — per-host HTTP pools configured at startup (`application.ex`, lines 255-276).

### Module Attributes for Constants

Module attributes and compile-time evaluation:

```elixir
# lib/plausible/billing/plans.ex — loads plan JSONs at compile time
@generations [:legacy_plans, :plans_v1, :plans_v2, :plans_v3, :plans_v4, :plans_v5]
for group <- Enum.flat_map(@generations, &[&1, :"sandbox_#{&1}"]) do
  path = Application.app_dir(:plausible, ["priv", "#{group}.json"])
  plans_list = for attrs <- path |> File.read!() |> Jason.decode!() do
    %Plan{} |> Plan.changeset(attrs) |> Ecto.Changeset.apply_action!(nil)
  end
  Module.put_attribute(__MODULE__, group, plans_list)
end
```

### `on_ee` / `on_ce` — Build-Time Feature Injection

The `Plausible` module (`lib/plausible.ex`) provides macros that conditionally compile different code paths based on the Mix env:

```elixir
# lib/plausible.ex, lines 59-73
defp do_on_ee(do: do_block, else: else_block) do
  if ee?() do
    quote do: unquote(do_block)
  else
    quote do: unquote(else_block)
  end
end
```

Used pervasively for EE-only features (SSO, consolidated views, billing quotas) vs CE stubs.

---

## 7. Feature Flags (fun_with_flags)

### Configuration (`config/config.exs`, line 54-57):

```elixir
config :fun_with_flags, :cache_bust_notifications, enabled: false
config :fun_with_flags, :persistence,
  adapter: FunWithFlags.Store.Persistent.Ecto
```

### Actor Implementations

Three `FunWithFlags.Actor` protocol implementations:

- **`Plausible.Auth.User`** (`lib/plausible/auth/user.ex`, line 288): `"user:#{user.id}"`
- **`Plausible.Site`** (`lib/plausible/site.ex`, line 246): `"site:#{site.domain}"`
- **`Plausible.Teams.Team`** (`lib/plausible/teams/team.ex`, line 6): `"team:#{team.id}"`
- **`BitString`** (`lib/plausible_web/controllers/api/external_controller.ex`, line 1): identity

### Usage in Plugs

`PlausibleWeb.Plugs.FeatureFlagCheckPlug` (`lib/plausible_web/plugs/feature_flag_check_plug.ex`) gates routes:

```elixir
def call(%Plug.Conn{} = conn, flags) do
  if validate(conn.assigns[:current_user], conn.assigns.site, flags) do
    conn
  else
    PlausibleWeb.Api.Helpers.not_found(conn, "Not found")
  end
end

defp validate(current_user, site, flags),
  do: Enum.all?(flags, fn flag ->
    FunWithFlags.enabled?(flag, for: current_user) ||
      FunWithFlags.enabled?(flag, for: site)
  end)
```

### UI Admin Panel

On EE builds, `FunWithFlags.UI.Router` is mounted at `/flags` behind a `SuperAdminOnlyPlug`:

```elixir
# router.ex, lines 127-131
scope path: "/flags" do
  pipe_through :flags
  forward "/", FunWithFlags.UI.Router, namespace: "flags"
end
```

### Flag Check Pattern in Controllers

```elixir
# stats_controller.ex, line 439
{flag, FunWithFlags.enabled?(flag, for: user) || FunWithFlags.enabled?(flag, for: site)}
```

---

## 8. Background Jobs (Oban)

### Configuration (`config/runtime.exs`, lines 882-900)

```elixir
config :plausible, Oban,
  repo: Plausible.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: thirty_days_in_seconds},
    {Oban.Plugins.Cron, crontab: if(cron_enabled, do: crontab, else: [])},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(120)},
    {Oban.Plugins.Reindexer, schedule: "0 1 * * *"}
  ],
  queues: if(cron_enabled, do: queues, else: []),
  peer: if(cron_enabled, do: Oban.Peers.Postgres, else: false)
```

### Cron Schedule (`runtime.exs`, lines 806-846)

Base (self-hosted) + Cloud cron:

```elixir
base_cron = [
  {"0 0 * * *", Plausible.Workers.RotateSalts},
  {"0 * * * *", Plausible.Workers.ScheduleEmailReports},
  {"0 * * * *", Plausible.Workers.SendSiteSetupEmails},
  {"0 12 * * *", Plausible.Workers.SendCheckStatsEmails},
  {"*/15 * * * *", Plausible.Workers.TrafficChangeNotifier},
  # ...
]
cloud_cron = [
  {"0 12 * * *", Plausible.Workers.SendTrialNotifications},
  {"0 14 * * *", Plausible.Workers.CheckUsage},
  {"0 15 * * *", Plausible.Workers.NotifyAnnualRenewal},
  # ...
]
```

### Queue Configuration (22 queues total, `runtime.exs`, lines 848-875)

```elixir
base_queues = [
  rotate_salts: 1, schedule_email_reports: 1, send_email_reports: 1,
  spike_notifications: 1, check_stats_emails: 1, site_setup_emails: 1,
  clean_invitations: 1, clean_user_sessions: 1, analytics_imports: 1,
  analytics_exports: 1, notify_exported_analytics: 1,
  domain_change_transition: 1, check_accept_traffic_until: 1,
  clickhouse_clean_sites: 1, locations_sync: 1
]
cloud_queues = [
  trial_notification_emails: 1, check_usage: 1, notify_annual_renewal: 1,
  lock_sites: 1, legacy_time_on_page_cutoff: 1, purge_cdn_cache: 1,
  sso_domain_ownership_verification: 32, score_trial_prospects: 1
]
```

### Worker Pattern

**Simple worker** (`lib/workers/rotate_salts.ex`):
```elixir
defmodule Plausible.Workers.RotateSalts do
  use Oban.Worker, queue: :rotate_salts
  @impl Oban.Worker
  def perform(_job) do
    Plausible.Session.Salts.rotate()
  end
end
```

**Parameterized worker** with Ecto queries and sub-jobs (`lib/workers/schedule_email_reports.ex`):
```elixir
def perform(_job) do
  schedule_weekly_emails()
  schedule_monthly_emails()
end

defp schedule_weekly_emails() do
  # Query sites without pending jobs
  for site <- sites do
    SendEmailReport.new(%{site_id: site.id, interval: "weekly"},
      scheduled_at: monday_9am(site.timezone)
    ) |> Oban.insert!()
  end
end
```

**Worker with unique constraints** (`lib/workers/export_analytics.ex`):
```elixir
use Oban.Worker,
  queue: :analytics_exports,
  max_attempts: 3,
  unique: [period: 300, states: [:available, :scheduled, :executing]]
```

### Pro Features Used

- **`Oban.Plugins.Cron`** — crontab-based scheduling
- **`Oban.Plugins.Pruner`** — auto-cleanup of old jobs
- **`Oban.Plugins.Lifeline`** — rescue orphaned jobs
- **`Oban.Plugins.Reindexer`** — periodic index maintenance
- **`Oban.Peers.Postgres`** — peer-based leader election (for cron)
- **`Oban.insert!()` / `Oban.Job` queries** — workers dynamically schedule other workers

### Worker Naming Convention

All workers follow: `Plausible.Workers.<ActionName>` in `lib/workers/<action_name>.ex`.

---

## 9. GenServer Usage

Eight custom GenServers found:

| GenServer | Location | Purpose |
|---|---|---|
| `Plausible.Session.Balancer` | `lib/plausible/session/balancer.ex` | Serializes session writes per user_id (avoiding locks) |
| `Plausible.Session.BalancerSupervisor` | `lib/plausible/session/balancer_supervisor.ex` | Supervises 10-100 Balancer workers + Registry |
| `Plausible.Ingestion.WriteBuffer` | `lib/plausible/ingestion/write_buffer.ex` | Buffers incoming events before bulk ClickHouse insert |
| `Plausible.Event.WriteBuffer` | `lib/plausible/event/write_buffer.ex` | Event-level write buffer |
| `Plausible.Session.WriteBuffer` | `lib/plausible/session/write_buffer.ex` | Session-level write buffer |
| `Plausible.Imported.Buffer` | `lib/plausible/imported/buffer.ex` | Buffer for imported data writes |
| `Plausible.Session.Salts` | `lib/plausible/session/salts.ex` | Manages session salt rotation |
| `Plausible.Session.Transfer.TinySock` | `lib/plausible/session/transfer/tinysock.ex` | Unix domain socket server for session transfer |
| `Plausible.Session.Transfer.Alive` | `lib/plausible/session/transfer/alive.ex` | Keeps transfer server alive until takeover completes |
| `Plausible.InternalStatsApiVersion` | `lib/plausible/internal_stats_api_version.ex` | Manages stats API version state |
| `Plausible.RateLimit` | `lib/plausible/rate_limit.ex` | ETS-based rate limiter with periodic cleanup |

### Balancer Supervisor Pattern (`lib/plausible/session/balancer_supervisor.ex`)

Creates N workers that serialize processing by user_id, avoiding database locks:

```elixir
def init(size) do
  children = for id <- 1..size do
    %{id: id, start: {Plausible.Session.Balancer, :start_link, [id]}, restart: :permanent}
  end
  Supervisor.init([{Registry, [keys: :unique, name: ...]} | children], strategy: :one_for_one)
end
```

### Supervision Tree (`lib/plausible/application.ex`)

The main supervision tree includes:

1. `PartitionSupervisor` for User-Agent parsing tasks
2. `Plausible.Session.BalancerSupervisor` — 10-100 balancer children
3. `Plausible.Ingestion.Counters` — GenServer for ingestion counters
4. `Plausible.Session.Salts` — salt management GenServer
5. No explicit ETS table in supervision but `Plausible.RateLimit` creates a named ETS table
6. `Plausible.Cache.Adapter` child specs for multiple caches (with configurable TTL)
7. Multiple `Plausible.Cache.Warmer` child specs (periodic cache refresh)
8. `Plausible.Session.Transfer` — session cross-deployment migration supervisor
9. `{Oban, config}` — started as a child

### Cache Warming Pattern

Periodically refreshed ETS caches for performance-sensitive lookups:

```elixir
# lib/plausible/cache/warmer.ex
warmed_cache(Plausible.Site.Cache,
  adapter_opts: [n_lock_partitions: 1, ttl_check_interval: false, ...],
  warmers: [
    refresh_all:
      {Plausible.Site.Cache.All,
       interval: :timer.minutes(15) + Enum.random(1..:timer.seconds(10))},
    refresh_updated_recently:
      {Plausible.Site.Cache.RecentlyUpdated, interval: :timer.seconds(30)}
  ]
)
```

Caches used: `:sites_by_domain`, `:customer_currency`, `:user_agents`, `:sessions`,
`Plausible.Shield.*RuleCache` (4 caches), `Plausible.ConsolidatedView.Cache` (EE),
`Plausible.Stats.SamplingCache` (EE), `Plausible.Site.TrackerScript*Cache`.

---

## 10. Protocol Usage

### Protocol `defimpl` Definitions (12 found)

| Protocol | For | File:Line |
|---|---|---|
| `FunWithFlags.Actor` | `Plausible.Site` | `site.ex:246` |
| `FunWithFlags.Actor` | `Plausible.Teams.Team` | `teams/team.ex:6` |
| `FunWithFlags.Actor` | `Plausible.Auth.User` | `auth/user.ex:288` |
| `FunWithFlags.Actor` | `BitString` | `controllers/api/external_controller.ex:1` |
| `Jason.Encoder` | `Plausible.Goal` | `goal.ex:294` |
| `Jason.Encoder` | `Plausible.Annotations.Annotation` | `annotations/annotation.ex:190` |
| `Jason.Encoder` | `Plausible.Stats.QueryResult` | `stats/query_result.ex:330` |
| `Jason.Encoder` | `URI` | `ingestion/request.ex:422` |
| `Jason.Encoder` | `Plausible.Ingestion.Request` | `ingestion/request.ex:426` |
| `String.Chars` | `Plausible.Goal` | `goal.ex:307` |
| `Phoenix.HTML.Safe` | `Plausible.Goal` | `goal.ex:313` |
| `Bamboo.Formatter` | `Plausible.Auth.User` | `auth/user.ex:282` |

### Custom Behaviours

| Behaviour | Module | Callbacks |
|---|---|---|
| `Plausible.Billing.Feature` | `feature.ex` | `name/0`, `display_name/0`, `toggle/3`, `enabled?/1`, `opted_out?/1`, `check_availability/1` |
| `Plausible.Cache` | `cache.ex` | `name/0`, `child_id/0`, `count_all/0`, `base_db_query/0`, `get_from_source/1` |
| `Plausible.Imported.Importer` | `imported/importer.ex` | `name/0`, `label/0`, `parse_args/1`, `import_data/2`, + 4 optional callbacks |
| `Plausible.Audit.Encoder` | `audit/repo.ex` | Custom protocol for audit-log serialization |

### Feature Module as Behaviour Usage

Each feature (`Plausible.Billing.Feature.Props`, `.Funnels`, `.Goals`, etc.) uses the `Plausible.Billing.Feature` module via `__using__`:

```elixir
defmodule Plausible.Billing.Feature.Props do
  use Plausible.Billing.Feature,
    name: :props,
    display_name: "Custom Properties",
    toggle_field: :props_enabled
end
```

This generates `name/0`, `display_name/0`, `toggle/3`, `enabled?/1`, `opted_out?/1`, and `check_availability/1` automatically via the `__using__` macro.

---

## Key Architectural Takeaways

1. **Dual build system** (`on_ee` / `on_ce` macros) — EE features are conditionally compiled, with CE providing stub implementations via the clever `always/1` macro that tricks Dialyzer.

2. **ClickHouse + Postgres dual-database** — Postgres for relational data, ClickHouse for analytics events/sessions. Five Ecto repos, with custom `parallel_tasks` for ClickHouse.

3. **Ingestion pipeline as function composition** — Events flow through a chain of pure functions with telemetry instrumentation, buffered and batch-inserted into ClickHouse.

4. **Cache-heavy architecture** — 8+ different ETS-based caches with periodic warmers via GenServer processes, all with a common `Plausible.Cache` behaviour.

5. **Contexts as service layer** — No formal service/action/command objects. Context modules (plural names) compose schemas and provide the transactional interface. `Ecto.Multi` handles multi-step transactions.

6. **Oban for everything async** — 22 workers, cron scheduling, job-chaining (schedule → send), unique jobs, and telemetry-based error reporting.

7. **Config-driven dependency injection** — Backends (persistor, Paddle, geo, mailer) selected via application config, not environment-specific code.

8. **Feature flags + billing gating** — Two-layer gating: `fun_with_flags` for internal feature flags with per-user/site/toggle, and `Plausible.Billing.Feature` behaviour for plan-based feature availability.
