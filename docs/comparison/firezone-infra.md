# Firezone Infrastructure & CI/CD Patterns

A detailed analysis of the Firezone monorepo, focusing on the Elixir backend (Portal) and overall project infrastructure.

---

## Table of Contents

1. [Repository Structure](#1-repository-structure)
2. [GitHub Actions Workflows](#2-github-actions-workflows)
3. [Docker & Containerization](#3-docker--containerization)
4. [Secrets & Env Management](#4-secrets--env-management)
5. [Elixir Configuration System](#5-elixir-configuration-system)
6. [Release Build](#6-release-build)
7. [Clustering](#7-clustering)
8. [CI Checks for Elixir](#8-ci-checks-for-elixir)
9. [Database](#9-database)
10. [Asset Pipeline](#10-asset-pipeline)
11. [Package Distribution](#11-package-distribution)
12. [Nix Integration](#12-nix-integration)
13. [Key Patterns & Takeaways](#13-key-patterns--takeaways)

---

## 1. Repository Structure

Firezone is a **polyglot monorepo** with four main language ecosystems:

```
firezone/
├── elixir/            # Portal (control plane) — Phoenix app
├── rust/              # Data plane — gateway, client, relay
├── swift/apple/       # Apple client
├── kotlin/android/    # Android client
├── .github/
│   ├── workflows/     # 20+ workflow files
│   └── actions/       # 20 reusable composite actions
├── docker-compose.yml # Top-level orchestration (dev + CI)
├── scripts/
│   ├── compose/       # Compose fragments (portal.yml, client.yml, etc.)
│   ├── tests/         # Integration & perf test scripts
│   ├── build/         # Signing helpers
│   ├── upload/        # GH release, nix-cache, azure blob uploaders
│   └── nix/           # Nix helpers
├── flake.nix          # Nix flake for building all components
├── flake.lock
├── mise.toml          # Monorepo tooling config (mise)
└── policy-templates/  # OpenPolicyAgent rego policies
```

---

## 2. GitHub Actions Workflows

### 2.1 Architecture: "Planner + Reusable Workflows"

The CI system uses a **smart planner pattern**. The top-level `ci.yml` (`.github/workflows/ci.yml`) runs a `planner` job that **diffs changed files** against the base branch and decides which language-specific workflows to invoke:

**ci.yml lines 36–162** — The planner:
```yaml
jobs:
  planner:
    runs-on: ubuntu-latest
    outputs:
      jobs_to_run: ${{ steps.plan.outputs.jobs_to_run }}
    steps:
      - uses: actions/checkout@v7
      - name: Plan jobs to run
        id: plan
        run: |
          jobs="elixir,rust,tauri,kotlin,swift,codeql,control-plane,data-plane,loadtest,nix";
          # ... conditional logic based on changed paths ...
          if grep -q '^elixir/' changed_files.txt; then
            jobs="${jobs},elixir,codeql,control-plane,data-plane"
          fi
```

Key decisions:
- **Always run all** on `main`, `workflow_dispatch`, or `workflow_call`
- On PRs/merge groups: detect changed paths and run **only affected subsystems**
- If `.github/`, `.tool-versions`, or `docker-compose.yml` changes → run **everything**

### 2.2 Workflow Naming Convention

- `ci.yml` — Main CI (PR + merge_group)
- `cd.yml` — Continuous Delivery (pushes to `main`)
- `publish-release.yml` — Release publishing (GitHub Release published)
- `_*.yml` — **Reusable workflows** (callable via `workflow_call`)
- `perf.yml` — Manual performance test trigger

### 2.3 Reusable Workflow Catalog

| File | Purpose |
|---|---|
| `_elixir.yml` | Compile, test, dialyzer, static analysis |
| `_rust.yml` | Clippy, test, doc, fuzz, tunnel proptest |
| `_control-plane.yml` | Build & push Elixir Docker images (portal + elixir) |
| `_data-plane.yml` | Build Rust binaries + Docker images for client/gateway/relay |
| `_integration_tests.yml` | Docker Compose-based integration tests |
| `_perf_tests.yml` | Performance benchmarks (iperf3, secnetperf) |
| `_loadtest.yml` | Cross-platform loadtest binary builds |
| `_codeql.yml` | CodeQL analysis (JS/TS assets) |
| `_nix.yml` | Nix package builds with binary cache push |
| `_static-analysis.yml` | PR lint, link check, global linter |
| `_apt.yml` / `_rpm.yml` | Package repo metadata sync |

### 2.4 Merge Group Fast-Fail/Cancel Pattern

Every job uses `fail-fast: ${{ github.event_name == 'merge_group' }}` and every job has a **monitor** that cancels the run on failure in merge_group context (ci.yml lines 254–263):

```yaml
monitor-elixir:
  needs: [elixir]
  if: "!cancelled() && needs.elixir.result == 'failure' && github.event_name == 'merge_group'"
  runs-on: ubuntu-latest
  permissions:
    actions: write
  steps:
    - run: gh run cancel ${{ github.run_id }}
```

### 2.5 Required-Check Aggregator

A single `required-check` job aggregates status from all language jobs (ci.yml line 164), used as the merge gate so the branch protection rule only needs one check name.

### 2.6 Composite Actions

20 reusable actions in `.github/actions/`:

| Action | Purpose |
|---|---|
| `setup-elixir` | Erlang/Elixir version, deps cache, compile |
| `setup-postgres` | Start Postgres container with WAL level logical |
| `setup-rust-stable` | Rust toolchain install |
| `setup-rust-sccache` | Azure-backed sccache for Rust compilation |
| `setup-mise` | Monorepo tooling (mise) |
| `ghcr-docker-login` | GHCR auth |
| `setup-azure-cli` | Azure CLI |
| `setup-azure-sign-tool` | Windows code signing |
| `setup-gpg` | GPG key import for package signing |
| `setup-tauri-v2` | Tauri v2 deps |
| `free-disk-space` | Free GH runner disk space |
| `winget-releaser` | Winget package submission |

### 2.7 Docker Cache Strategy

Control plane images (`_control-plane.yml` lines 57–96) use **GitHub Actions cache** (`type=gha`) with **scoped per-image-name** keys. On PRs: **read-only** cache. On `main`: **read/write** cache with `mode=max`:

```yaml
cache-from: |
  type=gha,scope=${{ matrix.image_name }}:${{ env.CACHE_TAG }}
  type=gha,scope=${{ matrix.image_name }}:main
# main branch only:
cache-to: |
  type=gha,scope=${{ matrix.image_name }}:${{ env.CACHE_TAG }},mode=max,ignore-error=true
```

---

## 3. Docker & Containerization

### 3.1 Elixir Dockerfile (`elixir/Dockerfile`)

A **multi-stage build** with three stages:

**Stage 1: `compiler`** (lines 5–56)
- Based on `hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-alpine-${ALPINE_VERSION}`
- Installs git, build-base, nodejs, npm, pnpm
- Copies `mix.exs`/`mix.lock` first for layer caching
- Fetches & compiles deps
- Installs and builds assets (pnpm, tailwind, esbuild)
- Compiles the app with `--force` when `GIT_SHA` changes
- **Used standalone** in CI for mix tasks (test, ecto.migrate, etc.)

**Stage 2: `builder`** (lines 62–72)
- Packages source code for Sentry (`mix sentry.package_source_code`)
- Runs `mix release ${APPLICATION_NAME}`

**Stage 3: `runtime`** (lines 77–121)
- Fresh Alpine base (minimal)
- Installs runtime deps including `curl`, `jq` (for cloud metadata), `tini` (zombie reaper)
- Creates `default` user (uid 1001) with OpenShift-compatible group (root group)
- Copies only the release artifact
- Uses **tini** as PID 1 entrypoint
- Default CMD: `bin/server`

```dockerfile
# elixir/Dockerfile lines 101–103 — OpenShift-compatible user
RUN adduser -s /bin/sh -u 1001 -G root -h /app -S -D default \
    && mkdir -p /var/run/firezone \
    && chmod -R ugo+rw /var/run/firezone
```

### 3.2 docker-compose.yml

A **single-file orchestration** with Compose `extends` pattern and YAML anchors:

```yaml
# docker-compose.yml lines 7–9 — Cluster config anchor
x-erlang-cluster: &erlang-cluster
  ERLANG_CLUSTER_ADAPTER: "Elixir.Cluster.Strategy.Epmd"
  ERLANG_CLUSTER_ADAPTER_CONFIG: '{"hosts":["portal@portal.cluster.local"]}'
```

Services are split across compose fragments in `scripts/compose/`:
- `portal.yml` — Postgres + common environment (secrets, feature flags, email)
- `resources.yml` — httpbin, iperf3, secnetperf test targets
- `client.yml` — Headless client
- `relay.yml` — STUN/TURN relay
- `router.yml` — Network namespace routers with netem
- `edgeshark.yml` — Traffic capture tooling

### 3.3 Network Topology

Multiple isolated Docker networks simulate realistic network topologies:
- `internet` — Public IP space (`203.0.113.0/24`)
- `app-internal` — Portal + Postgres
- `client-*-internal` — Per-client networks
- `gateway-internal` — Gateway network
- `relay-*-internal` — Per-relay networks
- `resources` — Test HTTP targets
- `dns_resources` — DNS test targets

Each service has a paired **router** container that adds `netem` latency and NAT masquerading.

### 3.4 No Reverse Proxy (Nginx/Caddy)

Firezone does NOT use a reverse proxy. The Phoenix app serves directly via **Bandit** HTTP server. Three separate endpoints run in the same BEAM:
- `PortalWeb.Endpoint` (port 8080) — Web UI
- `PortalAPI.Endpoint` (port 8081) — WebSocket API for clients
- `PortalOps.Endpoint` (port 8082) — Ops dashboard

The compose file maps ports from a router container that forwards traffic via `iptables`.

---

## 4. Secrets & Env Management

### 4.1 Approach

Firezone follows the **env-var-and-files** approach described in AGENTS.md:
- **Environment variables** for non-sensitive inputs
- **Secrets** passed as env vars from CI secrets, vaults, or .env files
- `sample.env` provides documented examples with safe defaults

### 4.2 Elixir Secrets Flow

Secrets are read at **runtime** via `System.get_env/1` in `config/runtime.exs`:

```elixir
# config/runtime.exs lines 3–5 — Prod-only env var loading
if config_env() == :prod do
  import Portal.Config, only: [env_var_to_config!: 1, env_var_to_config: 1]
```

The `Portal.Config.env_var_to_config!/1` function (in `lib/portal/config.ex`) reads env vars with type casting, validation, and default support:

```elixir
# lib/portal/config.ex lines 37–51
def env_var_to_config!(module \\ Definitions, key, env_var_to_config \\ System.get_env()) do
  case Fetcher.fetch_source_and_config(module, key, env_var_to_config) do
    {:ok, _source, value} -> value
    {:error, reason} -> Errors.raise_error!(reason)
  end
end
```

### 4.3 CI Secrets

Secrets are inherited via `secrets: inherit` in reusable workflow calls. The workflow references specific secrets by name:

```yaml
# _data-plane.yml line 139
azure-connection-string: ${{ secrets.SCCACHE_AZURE_CONNECTION_STRING }}
```

Azure authentication uses **OIDC** (no static keys):
```yaml
# _data-plane.yml lines 299–308
- name: Azure login (OIDC)
  uses: azure/login@v3
  with:
    client-id: ${{ secrets.AZURE_ARTIFACTS_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_ARTIFACTS_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_ARTIFACTS_SUBSCRIPTION_ID }}
    allow-no-subscriptions: true
```

### 4.4 Dev Environment

Development uses `.env` files (gitignored). `sample.env` documents required vars with comments pointing to where to find values (1Password vault, Google Cloud Console, Azure):

```
# sample.env lines 1–9
GOOGLE_OIDC_CLIENT_ID=681146968633-...
ENTRA_OIDC_CLIENT_ID=a52b1a5c-...
# Find this in the Engineering Vault
GOOGLE_SERVICE_ACCOUNT_KEY=
```

---

## 5. Elixir Configuration System

### 5.1 Config File Structure (`elixir/config/`)

```
config/
├── config.exs     # Base config (all envs), self-documenting
├── runtime.exs    # Prod runtime config (env vars → config)
├── dev.exs        # Dev overrides
├── prod.exs       # Prod overrides
└── test.exs       # Test overrides
```

### 5.2 Sophisticated Config Framework

Firezone built a **custom config framework** under `lib/portal/config/`:

```
lib/portal/config/
├── config.ex         # Public API: env_var_to_config!/1, fetch_config/1
├── definition.ex     # Defines `defconfig` macro
├── definitions.ex    # 1030 lines of configuration definitions
├── fetcher.ex        # Resolves values from env → DB → defaults
├── resolver.ex       # Process-dictionary overrides (for testing)
├── validator.ex      # Type validation
├── caster.ex         # Type casting (string → boolean, integer, etc.)
├── dumper.ex         # Serialization for DB storage
└── errors.ex         # Configuration error handling
```

**Precedence** (documented in `definitions.ex` lines 19–28):
1. Environment variables (highest)
2. Database values
3. Default values (lowest)

**`defconfig` macro example** (from `definitions.ex` line 55):
```elixir
defconfig(:region, :string, default: "")
defconfig(:oban_enabled, :boolean, default: true)
defconfig(:websocket_additional_origins, {:array, ",", :string},
  default: [],
  changeset: fn changeset, key ->
    Portal.Changeset.validate_uri(changeset, key)
  end
)
```

### 5.3 Database Config with Entra Auth

The runtime config handles **Entra (Azure AD) database authentication** by dynamically resolving passwords:

```elixir
# runtime.exs lines 19–29
database_password_opts =
  cond do
    env_var_to_config!(:database_entra_auth) ->
      [{:configure, {Portal.Azure.ManagedIdentity, :put_database_token, []}}]
    env_var_to_config(:database_password) ->
      [{:password, env_var_to_config!(:database_password)}]
    true -> []
  end
```

### 5.4 Database Connection Pools

Multiple **isolated connection pools** for different workloads:
- `Portal.Repo` — Default
- `Portal.Repo.Replica` — Read replica
- `Portal.Repo.Web` — Web requests
- `Portal.Repo.Api` — API requests
- `Portal.Repo.Poller` — CDC slot pollers
- Replica variants: `.Replica.Web`, `.Replica.Api`, `.Replica.Poller`

Pool size is dynamic: `:erlang.system_info(:logical_processors_available) * 2`

### 5.5 Rate Limiting

Three-tier rate limiting using the `hammer` library:
- `PortalWeb.RateLimit` — Web UI (10 req/s, burst 200)
- `PortalAPI.RateLimit` — API endpoints (10 req/s, burst 200)
- `PortalAPI.Sockets.RateLimit` — WebSocket connections (1 req/s, burst 1)
- `PortalAPI.Plugs.IngestionRateLimit` — Flow log ingestion (1 req/s, burst 1)

### 5.6 Test Config Overrides

Tests use process-dictionary overrides for per-test config isolation (`config.ex` lines 145–165):

```elixir
def put_env_override(app \\ :portal, key, value) do
  Process.put(pdict_key_function(app, key), merged_value)
  :ok
end
```

---

## 6. Release Build

### 6.1 Mix Release

Defined in `mix.exs` lines 207–220:

```elixir
defp releases do
  [
    portal: [
      include_executables_for: [:unix],
      validate_compile_env: true,
      applications: [
        portal: :permanent,
        opentelemetry_exporter: :permanent,
        opentelemetry_experimental: :permanent,
        opentelemetry: :temporary
      ]
    ]
  ]
end
```

### 6.2 Release Overlays

`rel/` directory:
- `env.sh.eex` — Runtime env setup script (templated into release)
- `vm.args.eex` — VM flags
- `env.bat.eex` — Windows env setup
- `overlays/bin/` — Additional scripts bundled into release

**`env.sh.eex` highlights** (lines 37–43):
- **Cloud metadata discovery**: GCE metadata API or AWS ECS metadata
- **Release distribution**: `name` mode with configurable hostname

```bash
# env.sh.eex lines 37–43
if [ "${RELEASE_HOST_DISCOVERY_METHOD}" = "gce_metadata" ]; then
  RELEASE_HOSTNAME=$(curl "http://metadata.google.internal/...")
elif [ "${RELEASE_HOST_DISCOVERY_METHOD}" = "aws_ecs_metadata" ]; then
  RELEASE_HOSTNAME=$(curl "${ECS_CONTAINER_METADATA_URI_V4}" | jq ...)
fi
```

**`vm.args.eex`** — Tuned Erlang VM:
```erlang
-kernel net_ticktime 15      % Faster dead node detection (~60s)
+SDio 20                     % More dirty IO schedulers
```

### 6.3 Sentry Integration

- Source code is packaged into the release (`mix sentry.package_source_code`)
- Environment detection is **automatic** from `API_EXTERNAL_URL` hostname
- Runtime config enables Sentry conditionally (lines 601–613)

---

## 7. Clustering

### 7.1 libcluster

Firezone uses `libcluster` (~> 3.3) for Erlang node discovery, declared in `mix.exs` line 99:

```elixir
{:libcluster, "~> 3.3"},
```

### 7.2 Cluster Supervisor

`Portal.Cluster` (`lib/portal/cluster.ex`) wraps `Cluster.Supervisor` with support for **dual strategies**:

```elixir
def init(_opts) do
  config = Portal.Config.fetch_env!(:portal, __MODULE__)
  adapter = Keyword.fetch!(config, :adapter)
  secondary_adapter = Keyword.get(config, :secondary_adapter)

  topologies = build_topologies(adapter, adapter_config, secondary_adapter, secondary_adapter_config)
  # ...
end
```

### 7.3 Custom Postgres Strategy

A **custom libcluster strategy** (`lib/portal/cluster/postgres_strategy.ex`, 370 lines) uses PostgreSQL `LISTEN/NOTIFY` for cloud-agnostic node discovery:

- **Heartbeat-based** discovery via `pg_notify`
- Graceful shutdown broadcasts `goodbye:` for immediate disconnect
- Stale node detection after `missed_heartbeats` intervals
- Threshold-based error logging for monitoring connected node count

```elixir
# Configuration example (from module docs)
ERLANG_CLUSTER_ADAPTER=Elixir.Portal.Cluster.PostgresStrategy
ERLANG_CLUSTER_ADAPTER_CONFIG='{"repo":"Portal.Repo","channel_name":"cluster","heartbeat_interval":5000,"missed_heartbeats":3,"node_count":12}'
```

### 7.4 Secondary Strategy Support

During rolling deploys (e.g., migrating from GCP labels to Postgres), both strategies can run **simultaneously**:

```elixir
# Primary: new PostgresStrategy
ERLANG_CLUSTER_ADAPTER=Elixir.Portal.Cluster.PostgresStrategy
# Secondary: old Google Compute Labels strategy (during transition)
ERLANG_CLUSTER_ADAPTER_SECONDARY=Elixir.Portal.Cluster.GoogleComputeLabelsStrategy
```

### 7.5 Compose Cluster Config

In `docker-compose.yml`, the cluster uses **Epmd strategy** for local dev:

```yaml
x-erlang-cluster: &erlang-cluster
  ERLANG_CLUSTER_ADAPTER: "Elixir.Cluster.Strategy.Epmd"
  ERLANG_CLUSTER_ADAPTER_CONFIG: '{"hosts":["portal@portal.cluster.local"]}'
```

---

## 8. CI Checks for Elixir

The `_elixir.yml` reusable workflow runs three parallel jobs:

### 8.1 unit-test (lines 6–56)

| Step | What |
|---|---|
| `mix compile --warnings-as-errors` | Compile with zero warnings |
| `ecto.create + ecto.migrate` | DB setup |
| `mix coveralls.lcov` | Test with coverage (ExCoveralls) |
| `dorny/test-reporter` | JUnit XML test report |
| `coverallsapp/github-action` | Send to Coveralls |

### 8.2 type-check (lines 58–84)

| Step | What |
|---|---|
| `mix compile --warnings-as-errors` | Compile again (MIX_ENV=dev) |
| `mix dialyzer --plt` | Build PLT |
| `mix dialyzer --format dialyxir` | Run Dialyzer |

### 8.3 static-analysis (lines 86–145)

| Step | What |
|---|---|
| `mix compile --force --warnings-as-errors` | Full recompile |
| `mix format --check-formatted` | Code formatting |
| `mix hex.audit` | Retired packages check |
| `mix deps.audit` | Vulnerable deps check |
| `mix sobelow --skip --exit` | Security scanner |
| `mix credo --strict` | Linting |
| `mix deps.unlock --check-unused` | Unused deps detection |
| **OpenAPI spec validation** | Validates spec against swagger validator |

### 8.4 OpenAPI Validation

A swagger-validator Docker service runs alongside, and the spec is validated via HTTP:

```yaml
services:
  swagger-validator:
    image: swaggerapi/swagger-validator-v2:latest
    ports: [8080:8080]
# Then in steps:
run: |
  mix openapi.spec.yaml --spec PortalAPI.ApiSpec
  result=$(curl --data-binary @openapi.yaml http://localhost:8080/validator/debug)
  echo "$result" | jq -e '.schemaValidationMessages | length == 0'
```

### 8.5 Sobelow Config

Custom sobelow exclusions in `mix.exs` aliases (line 192):

```elixir
sobelow: [
  "sobelow --skip -i Config.HTTPS,Config.Secrets,Config.CSWH,Config.CSRFRoute,Config.Headers --ignore-files lib/portal/dev/account_population.ex"
]
```

---

## 9. Database

### 9.1 Migrations

Two migration directories:
- `priv/repo/migrations/` — Standard migrations
- `priv/repo/manual_migrations/` — Manual migrations (opt-in via `RUN_MANUAL_MIGRATIONS`)

Mixed alias in `mix.exs` (lines 181–186):
```elixir
"ecto.migrate": [
  "ecto.migrate --migrations-path priv/repo/migrations --migrations-path priv/repo/manual_migrations"
]
```

### 9.2 CDC / Logical Replication

Firezone uses **PostgreSQL logical replication** for change data capture:

- `Portal.ChangeLogs.Consumer` — Audit trail (30+ tables, 5 min warning threshold)
- `Portal.Changes.Consumer` — Cache invalidation (5s poll interval)

Both use replication slots and publications, configured per-environment:
```elixir
config :portal, Portal.ChangeLogs.Consumer,
  replication_slot_name: "change_logs_slot",
  publication_name: "change_logs_publication",
  table_subscriptions: ~w[accounts actors groups ...]
```

The WAL level is set in compose: `postgres -c wal_level=logical`, and in CI setup: `postgres -c "wal_level=logical"`.

### 9.3 Seeds

Seeds run via `mix ecto.seed` alias which calls `priv/repo/seeds.exs`:
```elixir
"ecto.seed": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"]
```

### 9.4 Oban (Background Jobs)

Extensive Oban setup with **dedicated queues** for each integration:
- `default: 10` workers
- Per-integration scheduler (1) + sync (5) queues (entra, google, okta, splunk, datadog, etc.)
- Cron jobs for periodic maintenance (partition flow logs, delete expired tokens, sweep account deletions, etc.)
- Uses `Oban.Peers.Database` peer strategy for production

```elixir
# runtime.exs lines 360–395
config :portal, Oban,
  peer: Oban.Peers.Database,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(120)},
    {Oban.Plugins.Cron, crontab: oban_crontab}
  ],
  queues: [
    default: 10,
    entra_scheduler: 1,
    entra_sync: 5,
    # ... 20+ queue definitions
  ]
```

---

## 10. Asset Pipeline

### 10.1 esbuild + Tailwind

Standard Phoenix setup with minor customization (`mix.exs` lines 194–200):

```elixir
"assets.setup": [
  "cmd --shell cd assets && CI=true pnpm i",
  "tailwind.install --if-missing",
  "esbuild.install --if-missing"
],
"assets.build": ["tailwind portal", "esbuild portal"],
"assets.deploy": ["tailwind portal --minify", "esbuild portal --minify", "phx.digest"]
```

### 10.2 Dev Watchers

In `dev.exs` lines 186–188, watchers for live reload:
```elixir
watchers: [
  esbuild: {Esbuild, :install_and_run, [:portal, ~w(--sourcemap=inline --watch)]},
  tailwind: {Tailwind, :install_and_run, [:portal, ~w(--watch)]}
]
```

### 10.3 Tool Versions

Versions pinned in `elixir/.tool-versions`:
```
nodejs 22.20.0
pnpm 10.33.0
elixir 1.20.2-otp-29
erlang 29.0.3
```

### 10.4 Third-Party Icons

Uses `remixicons` GitHub dependency with spares checkout (mix.exs lines 156–162):
```elixir
{:remixicons,
 github: "Remix-Design/RemixIcon",
 sparse: "icons",
 tag: "v4.9.1",
 app: false, compile: false, depth: 1}
```

---

## 11. Package Distribution

### 11.1 APT Repository

Deb packages are built during CI (`_data-plane.yml`), uploaded to Azure Blob Storage, and APT metadata is regenerated via `_apt.yml`. A GPG key signs the repository.

### 11.2 RPM Repository

Similar flow for RPM packages via `_rpm.yml`, using `createrepo_c`.

### 11.3 Windows Code Signing

Windows binaries are signed using Azure Key Vault (`_data-plane.yml` lines 157–168):
```yaml
- uses: ./.github/actions/setup-azure-sign-tool
- run: ../scripts/build/sign.sh "$ARTIFACT_PATH"
  env:
    AZURE_KEY_VAULT_URI: ${{ secrets.AZURE_KEY_VAULT_URI }}
    AZURE_CERT_NAME: ${{ secrets.AZURE_CERT_NAME }}
```

### 11.4 Winget

GUI and headless clients are published to Windows Package Manager via `publish-release.yml` using a classic PAT for PR creation.

### 11.5 GitHub Releases

The `_data-plane.yml` workflow uses `release-drafter` for automated release drafts. Uploads are done via `scripts/upload/github-release.sh`.

### 11.6 Azure Blob Storage Binaries

Release binaries are stored in Azure Blob (`firezoneartifacts` account) for direct download.

---

## 12. Nix Integration

Firezone uses **Nix flakes** as a parallel build system (alongside Docker):

- `flake.nix` — Defines packages for gateway, headless client, GUI client
- Nix builds are **separate from Docker** but build the same Rust code
- First-party binary cache at `https://artifacts.firezone.dev/nix`
- CI keeps the cache warm on every `main` push
- Auto-remediation for pnpm hash drift (`_nix.yml` lines 95–146)

```yaml
# _nix.yml — Auto-fix pnpm hash drift
if grep -q 'hash mismatch in fixed-output derivation' build.log \
  && grep -q 'pnpm-deps' build.log; then
  ./scripts/nix/update-pnpm-hash.sh
  build
fi
```

---

## 13. Key Patterns & Takeaways

| Pattern | How Firezone does it |
|---|---|
| **CI planning** | Smart diff-based planner decides which jobs to run |
| **Docker caching** | GHA cache with `type=gha`, read-only on PRs, read/write on main |
| **Multi-arch builds** | QEMU + Docker Buildx with manifest list merging |
| **Secrets** | Inherited via `secrets: inherit`, OIDC for Azure, no static keys in repo |
| **Configuration** | Custom `defconfig` framework with env→DB→default precedence |
| **Database pools** | Isolated pools per workload (web/api/poller), each with replica variant |
| **Clustering** | libcluster with custom Postgres LISTEN/NOTIFY strategy |
| **Rolling deploys** | Dual clustering strategies during migrations |
| **Observability** | OpenTelemetry (traces + metrics), Sentry, logger_json, Telemetry |
| **CD** | GHCR Docker images + Azure Blob binaries + APT/RPM repos |
| **Nix** | Flake-based builds kept warm by CI, binary cache auto-push |
| **Merge group handling** | Fast-fail + cancel on failure, required-check aggregator |
| **Testing** | Unit, integration (Compose-based), compatibility (matrix), perf (Bencher) |
| **Fuzzing** | Rust fuzz targets for IP packet parsing |
| **Tunnel testing** | Property-based testing with proptest, coverage-harvesting |
