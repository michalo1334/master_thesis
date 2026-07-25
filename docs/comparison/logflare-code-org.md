# Logflare Code Organization & Design Patterns

> Analysis of `/tmp/comparison_repos/logflare` — a production Elixir/Phoenix system for log ingestion, routing, and backend-agnostic storage.

---

## 1. Overview

Logflare is a multi-tenant log-management platform. It ingests logs via HTTP/gRPC, processes them through a rule engine, fans out to 14 backend storage adaptors (ClickHouse, BigQuery, PostgreSQL, S3, Loki, Datadog, etc.), and serves SQL/API queries over the stored data.

**Stack highlights:** Elixir/Phoenix, Broadway (pipeline ingestion), ETS (buffering), Oban (async jobs), ConfigCat (feature flags), Cachex (caching), `:atomics` (lock-free counters), Rust NIFs (document mapping).

---

## 2. Module Structure

### `lib/logflare/` — Domain Logic (73 sub-directories)

```
lib/logflare/
├── backends/            # Adaptor pattern, ingestion pipelines
├── sources/             # Source CRUD, caching, routing
├── rules/               # Rule engine (LQL routing)
├── logs/                # LogEvent, processors, search, ingest transformers
├── endpoints/           # Query endpoint management
├── users/               # User cache, API
├── billing/             # Billing plans
├── config_cat/          # Feature flag cache wrapper
├── alerts/              # Alerting queries, scheduling
├── auth/                # Auth providers
├── mapper/              # Rust NIF document mapper
├── ecto/                # Custom Ecto types
├── google/              # GCP/BigQuery helpers
├── lql/                 # LQL (Logflare Query Language) parser
├── sql/                 # SQL parsing/translation
├── context_cache.ex     # Generic read-through cache pattern
├── application.ex       # OTP Application
├── repo.ex              # Ecto Repo
├── vault.ex             # Encyption vault
└── utils/               # Guards, chunked_round_robin, etc.
```

### `lib/logflare_web/` — Web Layer (MVC + LiveView)

```
lib/logflare_web/
├── controllers/         # Phoenix controllers
├── views/               # JSON/HTML views
├── templates/           # HEEx templates
├── live/                # LiveView modules
├── channels/            # Phoenix Channels (WebSockets)
├── components/          # Core components (HEEx)
├── plugs/               # Plugs (auth, CORS, etc.)
├── hooks/               # LiveView hooks
├── router.ex            # Phoenix router
└── endpoint.ex          # Phoenix Endpoint
```

### `lib/logflare_grpc/` — gRPC Service

- `lib/logflare_grpc/` contains protobuf-generated code for the gRPC ingest endpoint.

---

## 3. Phoenix Context Pattern

Logflare uses a **thin domain-context** pattern: context modules (`Logflare.Users`, `Logflare.Sources`, etc.) expose public API functions, while a `Cache` module per context wraps `Logflare.ContextCache` for transparent read-through caching.

### Example: `Logflare.Users` context

**`lib/logflare/users/users.ex`** — the context module with business logic:

```elixir
# (conceptual — delegates to Repo with random read-replica selection)
defmodule Logflare.Users do
  def get(id), do: Logflare.Repo.apply_with_random_repo(__MODULE__, :get, [id])
  def get_by(keyword), do: Logflare.Repo.apply_with_random_repo(__MODULE__, :get_by, [keyword])
  # ...
end
```

**`lib/logflare/users/cache.ex`** — wraps context in `ContextCache`:

```elixir
defmodule Logflare.Users.Cache do
  # lib/logflare/users/cache.ex, lines 1-48
  use Cachex.Spec

  def get(id), do: apply_repo_fun(__ENV__.function, [id])

  defp apply_repo_fun(arg1, arg2) do
    Logflare.ContextCache.apply_fun(Users, arg1, arg2)
  end
end
```

**`lib/logflare/context_cache.ex`** — generic read-through cache:

```elixir
defmodule Logflare.ContextCache do
  # lib/logflare/context_cache.ex, lines 46-56
  def apply_fun(context, fun, args) when is_atom(fun) do
    cache = cache_name(context)
    cache_key = {fun, args}
    fetch(cache, cache_key, fn ->
      Logflare.Repo.apply_with_random_repo(context, fun, args)
    end)
  end
end
```

**Key point:** Cache busting is reactive — the system subscribes to the database write-ahead log (WAL) via `ContextCache.bust_keys/1`, which uses ETS match specs to find and evict stale entries.

### Context list (key modules):

| Context | Module | Cache |
|---------|--------|-------|
| Users | `Logflare.Users` | `Logflare.Users.Cache` |
| Sources | `Logflare.Sources` | `Logflare.Sources.Cache` |
| Backends | `Logflare.Backends` | `Logflare.Backends.Cache` |
| Rules | `Logflare.Rules` | `Logflare.Rules.Cache` |
| Billing | `Logflare.Billing` | `Logflare.Billing.Cache` |
| KeyValues | `Logflare.KeyValues` | `Logflare.KeyValues.Cache` |
| Teams | `Logflare.Teams` | - |

---

## 4. Schema Modules — TypedEctoSchema

All Ecto schemas use `TypedEctoSchema` (a compile-time-validated schema macro). Examples:

### `Logflare.Sources.Source`

```elixir
# lib/logflare/sources/source.ex, line 125
typed_schema "sources" do
  field :name, :string
  field :token, Ecto.UUID.Atom, autogenerate: true
  field :metrics, :map, virtual: true
  field :bq_storage_write_api, :boolean, default: false
  field :drop_lql_filters, Ecto.LqlRules, default: []
  field :retention_days, :integer, virtual: true
  field :transform_copy_fields_parsed, {:array, :map}, virtual: true
  # ...
  belongs_to :user, User
  has_many :rules, Rule
  many_to_many :backends, Backend, join_through: "sources_backends"
end
```

### `Logflare.Backends.Backend`

```elixir
# lib/logflare/backends/backend.ex, lines 16-58
typed_schema "backends" do
  field :type, Ecto.Enum, values: Map.keys(@adaptor_mapping)
  field :config, :map, virtual: true
  field :config_encrypted, Logflare.Ecto.EncryptedMap   # <-- encrypted at rest
  field :default_ingest?, :boolean, source: :default_ingest
  belongs_to :user, User
  has_many :rules, Rule
  many_to_many :sources, Source, join_through: "sources_backends"
end
```

### `Logflare.LogEvent` (embedded schema)

```elixir
# lib/logflare/logs/log_event.ex, lines 24-46
typed_embedded_schema do
  field :body, :map, default: %{}
  field :valid, :boolean
  field :event_type, Ecto.Enum, values: [:log, :metric, :trace], default: :log
  field :retries, :integer, default: 0
  field :day_bucket, :integer
  embeds_one :pipeline_error, PipelineError do
    field :stage, :string
    field :type, :string
    field :message, :string
  end
end
```

### Custom Ecto Types (`lib/logflare/ecto/`)

| Type | Purpose |
|------|---------|
| `Logflare.Ecto.EncryptedMap` | AES-encrypted config storage at rest |
| `Logflare.Ecto.EctoUuidAtom` | Stores UUIDs as atoms (for source tokens) |
| `Logflare.Ecto.EctoLqlRulesT` | Serializes LQL rule-filter structs |
| `Logflare.Ecto.EctoTermT` | Any Erlang term serialization |
| `Logflare.Ecto.ClickHouse` | Custom ClickHouse Ecto adapter |

---

## 5. Backend Adaptor Pattern — The Core Abstraction

The **adaptor pattern** is the central design pattern. 14 backend adaptors implement a common `@behaviour`.

### Behaviour Definition

```elixir
# lib/logflare/backends/adaptor.ex, lines 168-305
@callback start_link(start_link_arg()) :: {:ok, pid()} | ...
@callback cast_config(param :: map()) :: Ecto.Changeset.t()
@callback validate_config(changeset :: Ecto.Changeset.t()) :: Ecto.Changeset.t()
@callback execute_query(query_identifier(), query(), opts :: Keyword.t()) ::
            {:ok, QueryResult.t()} | {:error, term()}
@callback format_batch([LogEvent.t()]) :: map() | list(map())
@callback ecto_to_sql(Ecto.Query.t(), opts :: Keyword.t()) :: ...
@callback send_alert(Backend.t(), AlertQuery.t(), [term()]) :: :ok | ...

# Optional callbacks:
@optional_callbacks supports_default_ingest?: 0,
                   consolidated_ingest?: 0,
                   transform_query: 3,
                   map_query_parameters: 4,
                   on_backend_config_changed: 1,
                   on_backend_deleted: 1,
                   redact_config: 1,
                   ...
```

### Adaptor Mapping

```elixir
# lib/logflare/backends/backend.ex, lines 16-31
@adaptor_mapping %{
  webhook:    Adaptor.WebhookAdaptor,
  elastic:    Adaptor.ElasticAdaptor,
  datadog:    Adaptor.DatadogAdaptor,
  sentry:     Adaptor.SentryAdaptor,
  postgres:   Adaptor.PostgresAdaptor,
  bigquery:   Adaptor.BigQueryAdaptor,
  loki:       Adaptor.LokiAdaptor,
  clickhouse: Adaptor.ClickHouseAdaptor,
  incidentio: Adaptor.IncidentioAdaptor,
  s3:         Adaptor.S3Adaptor,
  axiom:      Adaptor.AxiomAdaptor,
  otlp:       Adaptor.OtlpAdaptor,
  last9:      Adaptor.Last9Adaptor,
  syslog:     Adaptor.SyslogAdaptor
}
```

### Adaptor Supervisor Tree

Every `source × backend` combination gets its own `AdaptorSupervisor`:

```elixir
# lib/logflare/backends/adaptor_supervisor.ex, lines 13-35
def init({source, backend}) do
  adaptor_module = Adaptor.get_adaptor(backend)
  IngestEventQueue.upsert_tid({source.id, backend.id, nil})
  children = [
    {IngestEventQueue.QueueJanitor, source: source, backend: backend},
    {adaptor_module, {source, backend}}     # <-- the adaptor itself
  ]
  Supervisor.init(children, strategy: :one_for_one)
end
```

### ClickHouse Adaptor Example (most sophisticated)

`ClickHouseAdaptor` implements `@behaviour` and is also a `Supervisor`:

```elixir
# lib/logflare/backends/adaptor/clickhouse_adaptor.ex, lines 1-960
defmodule Logflare.Backends.Adaptor.ClickHouseAdaptor do
  @behaviour Logflare.Backends.Adaptor
  use Supervisor

  # Consolidated ingestion: all sources share one pipeline per backend
  def consolidated_ingest?, do: true                              # line 57

  # Supports default ingest
  def supports_default_ingest?, do: true                           # line 129

  # Sub-processes started in init:
  # lib/logflare/backends/adaptor/clickhouse_adaptor.ex, lines 658-692
  def init(%Backend{} = backend) do
    children = [
      CircuitBreaker.child_spec(backend),
      {DynamicPipeline, name: ..., pipeline: Pipeline, ...}
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end

  # Provisions ClickHouse tables on start
  def provision_ingest_tables(backend), do: ...                    # line 634

  # Inserts via native TCP protocol or HTTP
  def insert_log_events(backend, events, event_type, opts), do: ... # line 517
end
```

ClickHouse adaptor sub-modules in `clickhouse_adaptor/`:

| Module | Purpose |
|--------|---------|
| `Pipeline` | Broadway pipeline — batches, compresses, inserts |
| `Ingester` | HTTP-based RowBinary insert |
| `NativeIngester` | Native TCP protocol insert (faster) |
| `Provisioner` | DDL table creation |
| `CircuitBreaker` | Failure circuit breaker |
| `ConnectionManager` | Connection pool for querying |
| `QueryConnectionSup` | DynamicSupervisor for query connections |
| `QueryTemplates` | SQL template strings for DDL/grants |
| `RowBinaryEncoder` | RowBinary wire format encoder |
| `MappingConfigStore` | Shared mapping config for field coalescing |
| `EndpointUtils` | URL parsing helpers |
| `EncodingUtils` | Encoding utilities |

### Contrast: ClickHouse vs Postgres vs BigQuery

| Aspect | ClickHouse | BigQuery | Postgres | HTTP-based (webhook, Slack, etc.) |
|--------|-----------|----------|----------|-----------------------------------|
| Ingest type | Consolidated (all sources → shared table) | Per-source | Per-source | Per-source |
| Pipeline | ID-passing (pointer-based) | ID-passing | Full-event | Full-event |
| Batch size | 60,000 rows, 5s window | 500 rows or 6MB | 350 rows | 250 rows |
| Retry | 1 retry + circuit breaker | 0 retries | None | None |
| Table provisioning | Auto-create `otel_logs_<token>`, `otel_metrics_<token>`, `otel_traces_<token>` | BQ dataset/table per source via Schema | User-managed | N/A |
| Performance | Native TCP + zlib streaming | `tabledata.insertAll` or Storage Write API | `Ecto.insert_all` | HTTP POST via Tesla |

---

## 6. Broadway Pipelines — Ingestion Engine

Every adaptor gets one or more Broadway pipeline instances, managed by `DynamicPipeline`.

### `DynamicPipeline` — Auto-scaling Supervisor

```elixir
# lib/logflare/backends/dynamic_pipeline.ex, lines 1-414
defmodule Logflare.Backends.DynamicPipeline do
  use Supervisor

  # Options: name, pipeline module, pipeline_args, min/max_pipelines,
  #          resolve_count (fn for desired count), resolve_interval
  # Lines 44-71

  # A Coordinator GenServer periodically calls resolve_count and
  # adds/removes pipeline children accordingly
end
```

### Pipeline Structure

Every pipeline follows the same Broadway structure:

```
BufferProducer (GenStage) → transformer → processors → batchers
```

**BufferProducer** (`lib/logflare/backends/buffer_producer.ex`, 607 lines):
- GenStage producer pulling from `IngestEventQueue` (ETS)
- Supports ID-passing mode (emits `LogEventPointer`, not full events)
- Lock-free in-flight tracking via `:atomics`
- Demand-based backpressure with in-flight caps

### ClickHouse Pipeline (most optimized)

```elixir
# lib/logflare/backends/adaptor/clickhouse_adaptor/pipeline.ex, lines 1-523
def start_link(args) do
  Broadway.start_link(__MODULE__,
    name: name,
    producer: [
      module: {BufferProducer, [backend_id: ..., consolidated: true, id_passing: true]},
      transformer: {__MODULE__, :transform, ...},
      concurrency: 1
    ],
    processors: [default: [concurrency: 6, min_demand: 100, max_demand: 1_000]],
    batchers: [
      ch: [concurrency: 32, batch_size: 60_000, batch_timeout: 5_000]
    ],
    context: %{backend_id: backend.id}
  )
end
```

Key design choices in the ClickHouse pipeline:
- **ID-passing**: Producer emits lightweight `LogEventPointer` refs, not full events. Events stay in ETS generation store until resolved in `handle_batch`. Lines 124-137.
- **Streaming compression**: `handle_batch` streams each event through zlib deflate directly into a gzip payload — never materializes the full batch binary in memory. Lines 274-298.
- **Batch keying by `{event_type, day_bucket}`**: Each batch targets a single ClickHouse partition. Lines 146-149.
- **In-flight tracking via `:atomics`**: Sub-microsecond counter operations, no message passing. Lines 202-217.

### BigQuery Pipeline

```elixir
# lib/logflare/sources/source/bigquery/pipeline.ex, lines 1-665
# Per-source pipeline, also ID-passing
# BQ-specific: max 6MB per batch, storage write API fallback
# Lines 33-35, 78-88
```

### HTTP-based Pipeline (shared by webhook/Slack/etc.)

```elixir
# lib/logflare/backends/adaptor/http_based/pipeline.ex, lines 1-49
# Uses Tesla client, full-event passing (no pointers)
# Full-event mode — no id_passing
# Lines 24-47
```

---

## 7. IngestEventQueue — ETS-based Buffering

The central buffering system uses ETS tables for zero-copy, lock-free event passing between producers and consumers.

```elixir
# lib/logflare/backends/ingest_event_queue.ex, lines 1-1487
defmodule Logflare.Backends.IngestEventQueue do
  use GenServer

  # Two-tier storage model (Lines 684-719):
  # 1. Pointer table per {source_id, backend_id, pid} — lightweight 7-tuple rows
  # 2. Shared generation store per {source_id, backend_id} — holds full LogEvent bodies
  #    Rotated periodically by GenerationJanitor

  # add_to_table/3 — writes to both stores, round-robins across pipeline shards
  # pop_pending_pointers/2 — atomic claim via :ets.take (Lines 903-987)
  # pop_pending/2 — claim + resolve to full LogEvent (Lines 1039-1077)
  # lookup_event/2 — resolve pointer to full event (Lines 286-296)

  # Recent-events cache (Lines 335-376):
  #   Independent from generation store, longer TTL
  #   Written by BigQuery ack for "recent logs" visibility
end
```

**Queue data model:**
- **Pointer row:** `{event_id, generation_tid, gen_event_id, size, retries, event_type, day_bucket}`
- **Generation store key:** `{gen_event_id => full LogEvent}`
- **Key pattern:** `{source_id, backend_id, pid}` or `{:consolidated, backend_id, pid}` for consolidated queues

**Housekeeping processes (from `Backends.Supervisor`):**
- `GenerationJanitor` — rotates generation tables by age
- `MapperJanitor` — rotates mapping config caches
- `BufferCacheWorker` — periodic buffer housekeeping
- `QueueJanitor` (per queue) — truncates runaway buffers

---

## 8. Feature Flags (ConfigCat)

### Setup

```elixir
# lib/logflare/application.ex, lines 186-196
config_cat =
  case Application.get_env(:logflare, :config_cat_sdk_key) do
    nil -> []
    config_cat_key ->
      [
        Logflare.ConfigCatCache,
        {ConfigCat, [sdk_key: config_cat_key]}
      ]
  end
```

### Caching Wrapper

```elixir
# lib/logflare/config_cat/cache.ex, lines 1-38
defmodule Logflare.ConfigCatCache do
  # Cachex-backed with 100K entry limit, 10min expiration
  # Wraps ConfigCat SDK calls to avoid hot-path latency
  def child_spec(_) do
    # ...
    {Cachex, :start_link, [__MODULE__, [
      hooks: [Utils.cache_limit(100_000)],
      expiration: Utils.cache_expiration_min(10, 1)
    ]]}
  end
  def get(key), do: Cachex.get(__MODULE__, key)
  def fetch(key, fallback), do: Cachex.fetch(__MODULE__, key, fallback)
end
```

Usage in the domain looks like `Logflare.ConfigCatCache.get(:some_flag)`. The cache is **conditionally started** only in multi-tenant production environments.

---

## 9. Source → Rule → Backend Routing

### Source lifecycle

1. **Source start** — `Logflare.Backends.SourceSup` starts per source with:
   - `RateCounterServer`
   - `RecentInsertsCacher`
   - Notification servers (email, text, webhook, Slack)
   - Per-backend `AdaptorSupervisor` (one per source × backend combination)

2. **Rule evaluation** — `Logflare.Rules.Rule` has:
   ```elixir
   # lib/logflare/rules/rule.ex, lines 23-31
   typed_schema "rules" do
     field :sink, Ecto.UUID.Atom          # target module
     field :lql_filters, Ecto.LqlRules     # parsed filter rules
     field :lql_string, :string
     belongs_to :source, Source
     belongs_to :backend, Backend           # optional backend target
   end
   ```

3. **Ingestion path:**
   ```
   HTTP/gRPC → Logs.Processor.ingest/3 → Backends.ingest_logs/4
     → Rule matching (LQL engine) → route to matching backends
     → IngestEventQueue.add_to_table/3 → BufferProducer pops
     → Broadway pipeline → adaptor-specific insert
   ```

### `Backends.ingest_logs` — the routing hub

```elixir
# lib/logflare/backends.ex
def ingest_logs(batch, source, via_rule, allow_spooling?) do
  # 1. Write to fallback (default ingest backend)
  # 2. Match rules via LQL
  # 3. Write to matched backend queues
  # 4. Optionally spool to S3/GCS if configured
end
```

---

## 10. Oban Background Jobs

Oban is configured as a supervision tree child:

```elixir
# lib/logflare/application.ex, line 97
{Oban, Application.fetch_env!(:logflare, Oban)}
```

Key Oban workers (found via grepping `use Oban.Worker`):
- `AlertSchedulerWorker` — schedules periodic alert evaluation
- Various billing/email notification workers

---

## 11. GenServer & Supervision Patterns

### Custom GenServers

| Module | Purpose | Pattern |
|--------|---------|---------|
| `IngestEventQueue` | ETS buffer manager | Single GenServer owning multiple named ETS tables |
| `DynamicPipeline.Coordinator` | Pipeline scaling coordinator | Periodic `:check` via `Process.send_after` |
| `ActiveUserTracker` | Tracks active users via PubSub | Phoenix.Presence-like |
| `RateCounterServer` | Per-source rate counting | GenServer with periodic metrics emission |
| `CircuitBreaker` | ClickHouse circuit breaker | GenServer with state transitions |

### Custom Singleton Pattern

`lib/logflare/gen_singleton.ex` — custom global singleton wrapper:

```elixir
defmodule Logflare.GenSingleton do
  # Wraps GenServer start to ensure only one instance per name across the cluster
  # Uses :global name registration
end
```

### Key Supervision Trees

```
Application (Logflare.Supervisor)
├── Logflare.Repo
├── Logflare.Backends.Supervisor           (v2 pipeline infrastructure)
│   ├── IngestEventQueue                   (GenServer managing ETS buffers)
│   ├── ConsolidatedSup                    (DynamicSupervisor for consolidated backends)
│   ├── SourcesSup                         (PartitionSupervisor for per-source supervisors)
│   ├── SourceRegistry / BackendRegistry   (Registries for name resolution)
│   ├── GenerationJanitor                  (ETS generation rotation)
│   ├── MapperJanitor                      (Mapping config cache rotation)
│   ├── ClickHouse infra                   (MappingConfigStore, NativePoolSup, QueryConnectionSup)
│   └── Spool infrastructure               (ProducerSup, ConsumerSup, MemoryMonitor)
├── Logflare.Sources.Source.Supervisor     (per-source DynamicSupervisor)
│   └── For each source: SourceSup
│       ├── RateCounterServer
│       ├── Notification servers (email, text, webhook, Slack)
│       ├── BillingWriter
│       └── AdaptorSupervisor (per source×backend)
│           ├── QueueJanitor
│           └── Adaptor (e.g. ClickHouseAdaptor)
│               ├── CircuitBreaker
│               └── DynamicPipeline
│                   ├── Coordinator (GenServer)
│                   ├── Broadway pipeline #1
│                   ├── Broadway pipeline #2
│                   └── ...
├── LogflareWeb.Endpoint
├── Oban
├── Cluster.Supervisor                    (libcluster)
├── Logflare.ConfigCatCache               (Cachex)
└── Logflare.Vault                         (Cloak encryption)
```

---

## 12. Elixir Protocols

Protocol usage is light but purposeful:

| Protocol | Module | Lines |
|----------|--------|-------|
| `Jason.Encoder` | `Logflare.Backends.Backend` (inline `defimpl`) | backend.ex:125-156 |
| `Jason.Encoder` | `Logflare.Sources.Source` (via `@derive`) | source.ex:14-48 |
| `Jason.Encoder` | `Logflare.LogEvent`, `Rule`, `EndpointQuery` | various |
| Rust NIF Protocol | `NativeIngester.Protocol` | Implements ClickHouse native TCP wire format |

The `Jason.Encoder` for `Backend` is notable — it explicitly redacts secrets via the adaptor's `redact_config/1` callback:

```elixir
# lib/logflare/backends/backend.ex, lines 125-156
defimpl Jason.Encoder, for: __MODULE__ do
  def encode(value, opts) do
    adaptor = Backend.adaptor_mapping()[value.type]
    # ... redact via adaptor.redact_config/1
  end
end
```

The **NativeIngester.Protocol** (`lib/logflare/backends/adaptor/clickhouse_adaptor/native_ingester/protocol.ex`) implements the ClickHouse TCP wire protocol from scratch — VarUInt encoding, packet types, client/server handshake, columnar block serialization. 437 lines of bit-level protocol encoding.

---

## 13. Rust NIFs via `native/`

```elixir
# lib/logflare/mapper.ex, lines 1-64
defmodule Logflare.Mapper do
  # Two-phase workflow:
  # 1. compile!(%MappingConfig{}) → NIF resource reference
  # 2. map(document, compiled_ref, opts) → mapped document
  #
  # Used in ClickHouse pipeline for field coalescing (line 320-321)
end
```

The `native/` directory at project root contains Rust code compiled into NIFs (via `Cargo.toml`). This handles performance-critical document mapping for high-throughput pipelines.

---

## 14. Dependency Injection & Service Patterns

### No DI framework

Logflare does **not** use a DI framework. Dependencies are:
1. **Compile-time configuration** (`Application.get_env/3`) for feature toggles and connection settings
2. **Function arguments** — adaptors receive `%Backend{}` and `%Source{}` structs
3. **Process naming** via `{:via, module, {registry, key}}` tuples for Supervisor/GenServer resolution

### Backend name resolution

```elixir
# lib/logflare/backends.ex
# Convention for naming processes:
def via_source(source, mod, extra \\ nil)          # {:via, Registry, {Backends.SourceRegistry, key}}
def via_backend(backend, mod)                      # {:via, Registry, {Backends.BackendRegistry, key}}
```

### Backends module as facade

```elixir
# lib/logflare/backends.ex — the public API for the backends domain
defmodule Logflare.Backends do
  def ingest_logs(batch, source, via_rule, allow_spooling?)  # main entry point
  def ensure_source_sup_started(source)                       # dynamic supervision
  def get_default_backend(user)                               # config resolution
end
```

---

## 15. Key Architectural Takeaways

1. **Adaptor pattern is the core** — 14 backends implement a common `@behaviour` with optional callbacks. Config validation, query execution, ingestion, and connection testing are all polymorphic per adaptor.

2. **Consolidated vs per-source ingest** — ClickHouse uses consolidated ingest (one table per backend, all sources share it). BigQuery uses per-source tables. This is controlled by `consolidated_ingest?/0`.

3. **ETS as primary buffer** — The `IngestEventQueue` uses ETS tables for sub-millisecond buffering with no GC pressure. Two-tier design: pointer tables for routing, generation store for event bodies.

4. **ID-passing for high throughput** — ClickHouse and BigQuery pipelines pass `LogEventPointer`s through Broadway instead of full events, resolving events from ETS lazily at batch time. Other adaptors (Slack, webhook) pass full events.

5. **Dynamic pipeline scaling** — `DynamicPipeline` auto-scales Broadway pipeline count based on queue depth, allowing burst handling without over-provisioning.

6. **Lock-free counters** — `:atomics` module used for in-flight tracking across producer/consumer boundaries, avoiding GenServer bottlenecks.

7. **Reactive cache invalidation** — `ContextCache` busts cache entries via WAL events and ETS match specs, rather than TTL-only expiry.

8. **ConfigCat for feature flags** — Wrapped in Cachex with 10min TTL, conditionally started only in multi-tenant mode.

9. **Dual ingest path** — ClickHouse uses both HTTP and native TCP protocols for inserts, with automatic async insert routing for small batches.

10. **Circuit breaker pattern** — ClickHouse adaptor implements a `CircuitBreaker` that trips on `too many parts` errors, preventing cascading failures.
