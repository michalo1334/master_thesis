# Firezone Elixir — Code Organization & Design Patterns

> Based on exploration of `/tmp/comparison_repos/firezone/elixir/lib/`
> All line numbers reference files under that root.

---

## 1. Module Structure

### Top-level `lib/` layout

```
lib/
├── portal/          # Domain logic (the "business" layer)
├── portal_web/      # Phoenix web layer (LiveView, Controllers, Components)
├── portal_api/      # Phoenix API layer (WebSocket channels, JSON API)
├── portal_ops/      # Ops/admin endpoint
├── openid_connect/  # Standalone OIDC library
└── mix/             # Mix tasks
```

Each top-level app has a `__using__` module (`PortalWeb`, `PortalAPI`) that provides `use PortalWeb, :controller` etc — the standard Phoenix composable pattern.

**`lib/portal.ex` does not exist** — `Portal` is a directory only, no top-level `Portal` module.

### `lib/portal/` directory layout

The domain is organized into **three structural patterns**:

**Flat schemas** — single files at `lib/portal/<name>.ex`:
- `account.ex` — `Portal.Account`
- `actor.ex` — `Portal.Actor`
- `policy.ex` — `Portal.Policy`
- `resource.ex` — `Portal.Resource`
- `group.ex` — `Portal.Group`
- `device.ex` — `Portal.Device`
- `site.ex` — `Portal.Site`
- `membership.ex` — `Portal.Membership`
- etc (many more, ~80 files at root level)

**Subdirectory contexts** — directories that group related modules:
- `accounts/` — Account lifecycle and embedded schemas
- `actor/` — Per-actor type logic
- `policies/` — Policy conditions and evaluator
- `authentication/` — Auth context, credential, subject structs
- `changes/` — CDC change events + hooks
- `config/` — Config definition DSL
- `workers/` — Oban workers (20 modules)
- `billing/` — Stripe integration
- `cache/` — In-memory caches for gateways/clients
- `directory_sync/` — IdP sync
- `mailer/` — Email templates and delivery
- `repo/` — Repo extensions (filter, replica)
- `types/` — Custom Ecto types

**`Portal.Accounts.*`** — embedded schemas live inside `accounts/`:
- `Portal.Accounts.Features` — per-account feature flags (embedded)
- `Portal.Accounts.Limits` — per-account billing limits (embedded)
- `Portal.Accounts.Config` — per-account DNS, notification config (embedded)
- `Portal.Accounts.Deletion` — account deletion lifecycle service

### `lib/portal_web/` directory layout

```
portal_web/
├── components/          # Shared UI components (Core, Nav, Form, Table, Page)
├── controllers/         # Legacy controllers + HTML views (error, entra, etc.)
├── live/                # LiveView modules
│   ├── actors/          # Actor-related LiveViews
│   ├── groups/          # Group-related LiveViews
│   ├── policies/        # Policy-related LiveViews
│   ├── resources/       # Resource-related LiveViews
│   ├── clients/         # Client-related LiveViews
│   ├── sites/           # Site-related LiveViews
│   ├── settings/        # Settings sub-routes (api_clients, trust_anchors)
│   ├── sign_in/         # Auth LiveViews
│   └── logs/            # Log LiveViews
├── live_hooks/          # Phoenix LiveView hooks
├── plugs/               # Phoenix Plugs
├── session/             # Session handling
├── oidc/                # OIDC callback handling
└── cookie/              # Cookie management
```

### `lib/portal_api/` directory layout

```
portal_api/
├── client/          # Client WebSocket channel logic
│   ├── channel/     # Channel implementations
│   ├── v2/          # API version 2
│   └── views/       # Client views
├── gateway/         # Gateway WebSocket channels
│   ├── channel/
│   ├── v2/
│   └── views/
├── relay/           # Relay connections
├── controllers/     # JSON REST controllers
│   └── integrations/ # Stripe, Azure ACS webhooks
├── schemas/         # JSON:API schemas
├── sockets/         # Phoenix Socket definitions
└── plugs/           # API-specific plugs
```

---

## 2. Phoenix Contexts

Firezone **does not use Phoenix contexts** (`Contexts` module). Instead, domain logic lives in flat modules under `Portal.*`. There are no `Accounts`, `Actors`, `Policies` context modules wrapping the schemas.

Key difference: `Portal.Accounts` is **not** a context — it's a namespace for **embedded schemas** and account lifecycle operations:

- `Portal.Accounts.Features` (embedded schema)
- `Portal.Accounts.Limits` (embedded schema)
- `Portal.Accounts.Config` (embedded schema)
- `Portal.Accounts.Deletion` (service module)

The actual `Portal.Account` schema lives as a **flat file** directly under `lib/portal/`.

### How domain logic is organized instead

**Service modules** named for the operation, not the schema:

```elixir
# lib/portal/accounts/deletion.ex — service module, not a context
defmodule Portal.Accounts.Deletion do
  alias Portal.Account
  alias Portal.Mailer
  alias __MODULE__.Database     # nested Database module
  
  def schedule_account_deletion(%Account{} = account, attrs, subject) do
    # ...
  end
  
  defmodule Database do          # Embedded module for data access
    # Ecto queries, Safe.scoped, Safe.transact
  end
end
```

`Portal.Authentication` is the closest thing to a "context" — it's a large module (822 lines) coordinating token creation, verification, OTP, and portal sessions. But it's still a single module with a `Database` sub-module for queries.

---

## 3. Schema Modules (Ecto Schemas)

### Primary key pattern

All schemas use `binary_id` UUIDs and composite keys with `account_id`:

```elixir
# lib/portal/actor.ex:6-14
@primary_key false
@foreign_key_type :binary_id

schema "actors" do
  belongs_to :account, Portal.Account, primary_key: true
  field :id, :binary_id, primary_key: true, autogenerate: true
  # ...
end
```

Every multi-tenant entity belongs to `Portal.Account` with `primary_key: true`, making the PK composite `(account_id, id)`. This is a **sharding-ready design**.

### Embedded schemas heavy usage

Multiple `embeds_one` / `embeds_many` for configuration stored alongside the parent:

```elixir
# lib/portal/account.ex:24-28
embeds_one :features, Portal.Accounts.Features, on_replace: :delete
embeds_one :limits, Portal.Accounts.Limits, on_replace: :delete
embeds_one :config, Portal.Accounts.Config, on_replace: :update
embeds_one :metadata, Portal.Account.Metadata, on_replace: :update
```

**Inline embeds with `do` block** — embeds_with schema defined in parent:

```elixir
# lib/portal/resource.ex:42-45
embeds_many :filters, Filter, on_replace: :delete, primary_key: false do
  field :protocol, Ecto.Enum, values: [tcp: 6, udp: 17, icmp: 1]
  field :ports, {:array, Portal.Types.Int4Range}, default: []
end
```

### Changeset pattern

Changesets receive a pre-existing `%Ecto.Changeset{}` from the caller (called by `Safe.apply_schema_changeset/2`):

```elixir
# lib/portal/actor.ex:49-61
def changeset(%Ecto.Changeset{} = changeset) do
  changeset
  |> validate_required(~w[name type]a)
  |> trim_change(~w[name email]a)
  |> validate_length(:name, max: 255)
  |> validate_type_transition()
  |> normalize_email(:email)
  |> validate_email(:email)
  |> assoc_constraint(:account)
  |> unique_constraint(:email, name: :actors_account_id_email_index)
end
```

### Type specs on schemas

Many schemas provide explicit `@type t` struct specs:

```elixir
# lib/portal/policy.ex:11-23
@type t :: %__MODULE__{
  id: Ecto.UUID.t(),
  description: String.t() | nil,
  conditions: [Portal.Policies.Condition.t()],
  group_id: Ecto.UUID.t() | nil,
  # ...
}
```

---

## 4. Service / Action Objects

### Pattern: `Database` submodule inside service modules

The dominant pattern: keep **business logic** and **control flow** in the outer module, and **data access** in an inner `Database` module:

```elixir
# lib/portal/accounts/deletion.ex:82-223
defmodule Portal.Accounts.Deletion do
  def schedule_account_deletion(%Account{} = account, attrs, subject) do
    case Database.schedule_account_deletion(account, attrs, subject) do
      {:ok, {:transitioned, account}} -> enqueue_deletion_notification(account, subject)
      {:ok, {:unchanged, account}} -> {:ok, account}
      {:error, reason} -> {:error, reason}
    end
  end

  defmodule Database do
    def schedule_account_deletion(%Account{} = account, attrs, subject) do
      Safe.transact(fn ->
        with {:ok, transition} <- transition_account_deletion(account, attrs, :schedule, subject),
             {:ok, _job} <- maybe_insert_reminder_job(transition) do
          {:ok, transition}
        end
      end)
    end
  end
end
```

### Same pattern in workers:

```elixir
# lib/portal/workers/delete_account.ex:38-121
defmodule Portal.Workers.DeleteAccount do
  use Oban.Worker, queue: :default

  def perform(%Oban.Job{args: %{"account_id" => account_id}}) do
    case Database.transact_delete(account_id) do
      {:ok, {:deleted, account}} -> :ok
      # ...
    end
  end

  defmodule Database do
    def transact_delete(account_id) do
      Safe.transact(fn -> ... end)
    end
  end
end
```

### This pattern appears in the majority of modules:
- `Portal.Billing` / `Portal.Billing.Database`
- `Portal.Authentication` / `Portal.Authentication.Database`
- `Portal.Policy.Database` (nested in policy.ex)
- `Portal.Workers.CheckAccountLimits.Database`
- `Portal.Workers.PartitionFlowLogs.Database`
- `Portal.Mailer.Database`

### Transact pattern

Operations that need to execute side effects atomically with DB changes use `Safe.transact/1`:

```elixir
# lib/portal/authentication.ex:755-762
def insert_portal_session_with_log(session, log_attrs) do
  Safe.transact(fn ->
    with {:ok, session} <- insert_portal_session(session) do
      insert_session_log(log_attrs)
      {:ok, session}
    end
  end)
end
```

---

## 5. Dependency Injection

### Module attribute for compile-time config

```elixir
# lib/portal/safe.ex:12
@replica Application.compile_env(:portal, :replica_repo)
```

This resolves the replica repo module at **compile time**. The `:replica` atom delegates to this resolved module.

### Application env via `Portal.Config`

All configuration is fetched through `Portal.Config` rather than direct `Application.fetch_env!` calls:

```elixir
# lib/portal/billing.ex:609-611
defp fetch_config!(key) do
  Portal.Config.fetch_env!(:portal, __MODULE__)
  |> Keyword.fetch!(key)
end
```

### `Portal.Config` test overrides

In test environment, `Portal.Config.fetch_env!/2` checks process dictionary before `Application.fetch_env!`:

```elixir
# lib/portal/config.ex:127-139
def fetch_env!(app, key) do
  application_env = Application.fetch_env!(app, key)
  pdict_key_function(app, key)
  |> Portal.Config.Resolver.fetch_process_env()
  |> case do
    {:ok, override} -> override
    :error -> application_env
  end
end
```

This allows **per-process overrides** in tests without affecting other tests:

```elixir
# lib/portal/config.ex:100-101
def put_env_override(app \\ :portal, key, value) do
  Process.put(pdict_key_function(app, key), merged_value)
end
```

### Feature flag overrides in tests

```elixir
# lib/portal/config.ex:155-161
def feature_flag_override(feature, value) do
  enabled_features = fetch_env!(:portal, :enabled_features)
                    |> Keyword.put(feature, value)
  put_env_override(:enabled_features, enabled_features)
end
```

---

## 6. Feature Flags

### Two-level system

**Per-account features** (embedded in Account):

```elixir
# lib/portal/accounts/features.ex:1-16
defmodule Portal.Accounts.Features do
  use Ecto.Schema
  @primary_key false
  embedded_schema do
    field :policy_conditions, :boolean
    field :traffic_filters, :boolean
    field :idp_sync, :boolean
    field :rest_api, :boolean
    field :internet_resource, :boolean
    field :client_to_client, :boolean
    field :iceless, :boolean
    field :log_sinks, :boolean
  end
end
```

**Global feature toggles** controlled by environment (defconfig):

```elixir
# lib/portal/config.ex:85-88
def global_feature_enabled?(feature) do
  fetch_env!(:portal, :enabled_features)
  |> Keyword.fetch!(feature)
end
```

### Feature check pattern — compile-time code generation

Each feature gets a function generated at compile time:

```elixir
# lib/portal/account.ex:136-141
for feature <- Portal.Accounts.Features.__schema__(:fields), feature != :iceless do
  def unquote(:"#{feature}_enabled?")(account) do
    Config.global_feature_enabled?(unquote(feature)) and
      account_feature_enabled?(account, unquote(feature))
  end
end
```

This checks **both** the global toggle and the per-account feature flag.

### Global features schema

```elixir
# lib/portal/features.ex:1-11
defmodule Portal.Features do
  use Ecto.Schema
  @primary_key false
  schema "features" do
    field :feature, Ecto.Enum, values: [:client_to_client, :trust_anchors, :flow_logs]
    field :enabled, :boolean, default: false
  end
end
```

---

## 7. Background Jobs (Oban)

### Oban workers — `lib/portal/workers/` (20 workers)

All workers use `use Oban.Worker` with explicit queues:

```elixir
# lib/portal/workers/delete_account.ex:7-14
use Oban.Worker,
  queue: :default,
  max_attempts: 3,
  unique: [
    period: :infinity,
    states: :incomplete,
    keys: [:account_id]
  ]
```

**Unique jobs** prevent duplicates for idempotent operations, with `keys:` scoping the uniqueness constraint to job arguments.

### Worker types:

| Worker | Queue | Purpose |
|--------|-------|---------|
| `DeleteAccount` | `:default` | Hard-delete account after scheduled deletion |
| `SweepAccountDeletions` | `:default` | Enqueues `DeleteAccount` for expired accounts |
| `CheckAccountLimits` | `:default` | Batched limit checking every 30 min |
| `PartitionFlowLogs` | `:default` | Day-partition maintenance for flow_logs |
| `OutboundEmail` | `:outbound_emails` | Async email delivery via ACS |
| `DeleteExpired*` | `:default` | TTL cleanup (API tokens, sessions, OTPs, etc.) |
| `AccountDeletionReminder` | `:default` | Sends reminder 48h before deletion |
| `AccountDeletionCompleted` | `:default` | Notifies admins after deletion |
| `SyncErrorNotification` | `:default` | IdP sync error emails |
| `LogSinkErrorNotification` | `:default` | Log sink error emails |
| `OutdatedGateways` | `:default` | Notifies about outdated gateways |

### Job scheduling

Jobs insert other jobs for multi-step workflows:

```elixir
# lib/portal/workers/delete_account.ex:63-68
defp schedule_post_deletion_jobs(account, admin_emails) do
  with {:ok, _} <- maybe_insert_delete_subscription_job(account),
       {:ok, _} <- insert_completion_job(account, admin_emails) do
    {:ok, {:deleted, account}}
  end
end
```

### Oban start condition

Oban is only started when `oban_enabled` config is true:

```elixir
# lib/portal/application.ex:162-171
defp oban do
  if Portal.Config.env_var_to_config!(:oban_enabled) do
    [{Oban, Application.fetch_env!(:portal, Oban)}]
  else
    []
  end
end
```

---

## 8. GenServer Usage

### `Portal.Queue` — custom batched queue GenServer (246 lines)

A general-purpose, configurable batching queue:

```elixir
# lib/portal/queue.ex:1-246
defmodule Portal.Queue do
  use GenServer

  # Queue enqueues entries via GenServer.call/3
  # Processes them in batches on flush (timeout or threshold)
  # Runs a caller-provided on_flush callback for inserts

  def enqueue(server, attrs, opts \\ []) do
    GenServer.call(server, {:enqueue, attrs, opts})
  end
end
```

Key features:
- **Batcher with dispatch** — entries buffered and flushed at interval or threshold
- **Dispatch callback** runs synchronously in Queue process before enqueue (provides per-pid ordering guarantees)
- **Flush-on-terminate** — best-effort flush on supervisor shutdown
- Used for client session logs, gateway session logs, and policy authorization logs

### `Portal.Replication.SlotPoller` — WAL consumer GenServer (643 lines)

Custom GenServer for logical replication over pooled connections (no streaming replication):

```elixir
# lib/portal/replication/slot_poller.ex:1-643
defmodule Portal.Replication.SlotPoller do
  use GenServer
  
  # Polls pg_logical_slot_peek_binary_changes via regular SQL queries
  # Decodes pgoutput protocol messages
  # Dispatches to consumer callbacks (on_begin, on_write, on_logical_message, flush)
  # Holds session advisory lock for cluster leadership
end
```

Uses `handle_continue` for async batch flushing, advisory locks for leader election, and implements a behaviour (`@callback`).

---

## 9. Protocol Usage

### Custom protocol — `Portal.Cache.Cacheable`

A single custom protocol with implementations for 3 schema types:

```elixir
# lib/portal/cache/cacheable.ex:1-53
defprotocol Portal.Cache.Cacheable do
  def to_cache(struct)
end

defimpl Portal.Cache.Cacheable, for: Portal.Site do ... end
defimpl Portal.Cache.Cacheable, for: Portal.Resource do ... end
defimpl Portal.Cache.Cacheable, for: Portal.Policy do ... end
```

### Third-party protocol implementations

**Portal types** (`lib/portal/types/protocols.ex`):

```elixir
defimpl String.Chars, for: Postgrex.INET do ... end
defimpl JSON.Encoder, for: Postgrex.INET do ... end
defimpl String.Chars, for: Portal.Types.IPPort do ... end
defimpl String.Chars, for: Portal.Types.ProtocolIPPort do ... end
```

**Web layer** (`lib/portal_web/protocols.ex`):

```elixir
defimpl Phoenix.HTML.Safe, for: Postgrex.INET do ... end
defimpl Phoenix.HTML.Safe, for: Portal.Types.IPPort do ... end
defimpl Phoenix.HTML.Safe, for: Portal.Types.ProtocolIPPort do ... end
defimpl Phoenix.Param, for: Portal.Account do ... end
```

**Error handling** (`lib/portal_web/live_errors.ex`):

```elixir
defimpl Plug.Exception, for: PortalWeb.LiveErrors.BadRequest do ... end
defimpl Plug.Exception, for: PortalWeb.LiveErrors.NotFound do ... end
```

---

## 10. Domain Events — PubSub / Change Data Capture

### Dual-layer event system

#### 1. CDC-based events via PostgreSQL logical replication

**`Portal.Changes`** — WAL change data capture pipeline:

```
Postgres WAL → pg_logical_slot_peek_binary_changes → Portal.Replication.SlotPoller (GenServer)
  → Portal.Changes.Consumer (behaviour)
    → Portal.Changes.Hooks.* (per-table callbacks)
      → PubSub.Changes.broadcast/3 (Phoenix.PubSub)
      → Portal.PG.deliver/2 (targeted process delivery)
```

The `Consumer` maps table names to hook modules:

```elixir
# lib/portal/changes/consumer.ex:17-42
@tables_to_hooks %{
  "accounts" => Hooks.Accounts,
  "actors" => Hooks.Actors,
  "devices" => Hooks.Devices,
  "policies" => Hooks.Policies,
  "resources" => Hooks.Resources,
  # ... 20+ table mappings
}
```

**Hook behaviour** — 3 callbacks per table:

```elixir
# lib/portal/changes/hooks.ex:1-10
defmodule Portal.Changes.Hooks do
  @callback on_insert(lsn :: integer(), data :: map()) :: :ok | {:error, term()}
  @callback on_update(lsn :: integer(), old_data :: map(), data :: map()) :: :ok | {:error, term()}
  @callback on_delete(lsn :: integer(), old_data :: map()) :: :ok | {:error, term()}
end
```

**Example hook** — broadcasts to PubSub:

```elixir
# lib/portal/changes/hooks/actors.ex:7-12
def on_insert(lsn, data) do
  actor = struct_from_params(Portal.Actor, data)
  change = %Change{lsn: lsn, op: :insert, struct: actor}
  PubSub.Changes.broadcast(actor.account_id, :actors, change)
end
```

**Example hook** — targeted process delivery via PG:

```elixir
# lib/portal/changes/hooks/gateway_tokens.ex:13-17
def on_delete(_lsn, old_data) do
  token = struct_from_params(Portal.GatewayToken, old_data)
  PG.deliver(token.id, :disconnect)
  :ok
end
```

**Change struct**:

```elixir
# lib/portal/changes/change.ex:1-10
defmodule Portal.Changes.Change do
  defstruct [:lsn, :op, :old_struct, :struct]
  @type t :: %__MODULE__{
    lsn: integer(),
    op: :insert | :update | :delete,
    old_struct: struct() | nil,
    struct: struct() | nil
  }
end
```

#### 2. Phoenix.PubSub for runtime events

**`Portal.PubSub`** — thin wrapper:

```elixir
# lib/portal/pubsub.ex:1-103
defmodule Portal.PubSub do
  use Supervisor  # Runs as a named supervisor

  def broadcast(topic, payload) do
    Phoenix.PubSub.broadcast(__MODULE__, topic, payload)
  end
end
```

**Scoped PubSub** — `Portal.PubSub.Changes` provides entity-scoped topics:

```elixir
# lib/portal/pubsub.ex:46-102
defmodule Changes do
  @type entity :: :actors | :devices | :groups | :policies | :resources | ...

  def subscribe(account_id, entity) do
    entity_topic(account_id, entity) |> Portal.PubSub.subscribe()
  end

  def broadcast(account_id, entity, payload) do
    for topic <- [account_topic(account_id), entity_topic(account_id, entity)],
        node <- target_nodes(region) do
      Phoenix.PubSub.direct_broadcast!(node, Portal.PubSub, topic, payload)
    end
  end

  defp entity_topic(account_id, entity), do: "account:#{account_id}:#{entity}"
end
```

Multi-region: `direct_broadcast!` targets only nodes in the same region.

#### 3. Portal.PG — targeted cluster messaging

For **direct process-to-process messaging** (not broadcast), uses named `:pg` groups:

```elixir
# lib/portal/pg.ex:1-82
defmodule Portal.PG do
  def register(key) do
    # Disconnects existing registrant, then joins
    :pg.get_members(scope(), key)
    |> Enum.each(fn pid -> if pid != self, do: send(pid, :disconnect) end)
    :pg.join(scope(), key, self())
  end

  def deliver(key, message) do
    case :pg.get_members(scope(), key) do
      [] -> {:error, :not_found}
      pids -> Enum.each(pids, &send(&1, message))
    end
  end
end
```

Each process registers under its ID. The `:pg` scope is isolated to prevent an OTP bug in `pg.leave_remote/3` from affecting other parts of the system.

---

## 11. Authorization — `Portal.Safe`

The **central authorization module** for all DB operations. Every read/write goes through `Safe`.

### Scoped vs Unscoped

Two context structs:

```elixir
# lib/portal/safe.ex:14-37
defmodule Scoped do
  defstruct [:subject, :queryable, repo: Portal.Repo]
end

defmodule Unscoped do
  defstruct [:queryable, repo: Portal.Repo]
end
```

### Permissions as function clauses

```elixir
# lib/portal/safe.ex:910-1032
def permit(action, schema, %Subject{} = subject) do
  permit(action, schema, subject.actor.type)
end

# Account permissions
def permit(_action, Portal.Account, :account_admin_user), do: :ok
def permit(:read, Portal.Account, :api_client), do: :ok
# ~100+ clauses for specific schema + actor type combos
def permit(_action, _struct, _type), do: {:error, :unauthorized}   # catch-all
```

### Automatic account scoping

Queries are automatically filtered by `account_id`:

```elixir
# lib/portal/safe.ex:806-814
defp apply_account_filter(queryable, Portal.Account, account_id) do
  where(queryable, id: ^account_id)   # Account uses id, not account_id
end
defp apply_account_filter(queryable, _schema, account_id) do
  where(queryable, account_id: ^account_id)  # All others
end
```

### Replica support

```elixir
Safe.scoped(subject, :replica) |> Safe.all()        # reads from replica
Safe.scoped(subject) |> Safe.one()                   # reads from primary
Safe.scoped(subject, :replica) |> Safe.one(fallback_to_primary: true)  # fallback
```

### Replication stream subject emission

Every mutation emits the subject into the WAL for CDC consumers:

```elixir
# lib/portal/safe.ex:1035-1038
defp emit_subject_message(%Subject{} = subject) do
  message = subject |> Subject.to_map() |> JSON.encode!()
  Repo.query!("SELECT pg_logical_emit_message(true, 'subject', $1)", [message])
end
```

---

## 12. Config Definition DSL

### `defconfig` macro

Configuration is defined declaratively with types, defaults, validators, and docs:

```elixir
# lib/portal/config/definitions.ex:55-56
defconfig(:region, :string, default: "")

defconfig(:oban_enabled, :boolean, default: true)

defconfig(:web_external_url, :string,
  default: nil,
  changeset: fn changeset, key ->
    changeset
    |> Portal.Changeset.validate_uri(key, require_trailing_slash: true)
    |> Portal.Changeset.normalize_url(key)
  end
)
```

Supports typed values: `:string`, `:boolean`, `:integer`, arrays, embeds, `{:one_of, ...}`.

### Resolution chain

```
1. Environment variable (highest priority)
2. Database value
3. Default value (lowest priority)
```

---

## 13. Authentication Subject & Context

### `Subject` struct

The authenticated identity that flows through the system:

```elixir
# lib/portal/authentication/subject.ex:1-41
defmodule Portal.Authentication.Subject do
  @enforce_keys [:actor, :account, :credential, :expires_at, :context]
  defstruct actor: nil, account: nil, credential: nil, expires_at: nil, context: nil
end
```

### `Context` struct

Metadata about the authentication session (IP, geo, user agent):

```elixir
# lib/portal/authentication/context.ex:1-42
defmodule Portal.Authentication.Context do
  @enforce_keys [:type, :remote_ip, :user_agent]
  defstruct type: nil, remote_ip: nil, user_agent: nil,
            remote_ip_location_region: nil, # ...
end
```

### `Credential` struct

```elixir
# lib/portal/authentication/credential.ex (inferred)
defstruct [:type, :id, :auth_provider_id]
```

Supports token types: `:client_token`, `:api_token`, `:portal_session`.

---

## 14. Billing Module

### `Portal.Billing` (788 lines)

The billing module is atypical — it **combines configuration, logic, and database access** in one module with a nested `Database` module. It is essentially a service module for Stripe integration.

Key pattern — wraps third-party API in a thin client:

```elixir
# lib/portal/billing.ex:275-300
def create_customer(%Portal.Account{} = account) do
  secret_key = fetch_config!(:secret_key)
  with {:ok, %{"id" => customer_id}} <- APIClient.create_customer(secret_key, ...) do
    account |> update_account_metadata_changeset(%{customer_id: customer_id}) |> Database.update()
  end
end
```

Uses `Portal.Account.Metadata.Stripe` embedded schema to store Stripe metadata.

---

## 15. Changeset Module

### `Portal.Changeset` — shared validation helpers

```elixir
# lib/portal/changeset.ex
defmodule Portal.Changeset do
  import Ecto.Changeset

  def trim_change(changeset, fields) do ... end
  def validate_uri(changeset, key, opts \\ []) do ... end
  def validate_not_in_cidr(changeset, field, cidr, opts \\ []) do ... end
  # etc.
end
```

Used across all schema modules.

---

## Summary of Key Patterns

| Pattern | File / Module | Description |
|---------|--------------|-------------|
| **Flat schema files** | `lib/portal/<name>.ex` | No context wrappers for schemas |
| **`Database` submodule** | `Portal.*.Database` | Data access separated from business logic |
| **`Safe.scoped/3`** | `lib/portal/safe.ex` | Centralized authz + account scoping for DB ops |
| **Permission clauses** | `Safe.permit/3` | Pattern-matched by schema + actor type |
| **Embedded configs** | `Accounts.Features/Limits/Config` | JSON-in-column per-account config |
| **CDC events** | `Changes.Hooks.*` | WAL-based events → PubSub + PG |
| **Targeted messaging** | `Portal.PG` | `:pg` groups for per-process delivery |
| **Batching queue** | `Portal.Queue` | Configurable GenServer batcher |
| **Polled replication** | `Replication.SlotPoller` | SQL-based logical replication (no streaming) |
| **Oban unique jobs** | `workers/*.ex` | `unique: [keys: [...]]` for idempotence |
| **Chained workers** | `DeleteAccount → DeleteSubscription + AccountDeletionCompleted` | Multi-step job workflows |
| **Feature flags** | `Accounts.Features` + global `enabled_features` | Two-level (global ∧ per-account) |
| **Generated feature fns** | `Account.feature_enabled?/1` | Compile-time code generation from schema fields |
| **`defconfig` DSL** | `Config.Definition` | Declarative typed config with env override |
| **Protocol** | `Cache.Cacheable` | Only custom protocol; others are 3rd-party impls |
| **Test overrides** | `Portal.Config` | Process-dictionary config overrides |
| **Telemetry** | Various `Opentelemetry*.setup()` | OpenTelemetry for Ecto, Oban, Bandit, Phoenix |
