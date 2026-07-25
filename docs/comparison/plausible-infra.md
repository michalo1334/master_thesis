# Plausible Analytics — Infrastructure & CI/CD Report

> Repository: `plausible/analytics` (Community Edition)
>
> Analyzed: `/tmp/comparison_repos/plausible`

---

## Table of Contents

1. [GitHub Actions Workflows](#1-github-actions-workflows)
2. [Docker Build](#2-docker-build)
3. [Secrets & Environment Variable Management](#3-secrets--environment-variable-management)
4. [Configuration Organization](#4-configuration-organization)
5. [Deployment & Releases](#5-deployment--releases)
6. [Clustering (libcluster)](#6-clustering-libcluster)
7. [Reverse Proxy & TLS](#7-reverse-proxy--tls)
8. [CI Checks (Static Analysis & Linting)](#8-ci-checks-static-analysis--linting)
9. [Database — Multi-Repo Migrations](#9-database--multi-repo-migrations)
10. [Asset Pipeline](#10-asset-pipeline)

---

## 1. GitHub Actions Workflows

**Directory**: `.github/workflows/` — **14 workflows**.

### 1.1 Elixir CI (`elixir.yml`)

The largest workflow — ~300 lines. Runs on every PR, push to `master`/`stable`, and merge groups.

**Key patterns:**

- **Matrix builds** across `mix_env: ["test", "ce_test"]` with 6 test partitions each:
  ```yaml
  # .github/workflows/elixir.yml, lines 23-26
  matrix:
    mix_env: ["test", "ce_test"]
    postgres_image: ["postgres:18"]
    mix_test_partition: [1, 2, 3, 4, 5, 6]
  ```
- **Service containers** for Postgres and ClickHouse (pinned to `clickhouse/clickhouse-server:25.11.5.8-alpine`).
- **Parallel cache key** with `CACHE_VERSION: v18` pattern — cache key includes branch name with fallback to master:
  ```yaml
  # lines 74-77
  key: ${{ env.MIX_ENV }}-${{ env.CACHE_VERSION }}-${{ github.head_ref || github.ref }}-${{ hashFiles('**/mix.lock') }}
  restore-keys: |
    ${{ env.MIX_ENV }}-${{ env.CACHE_VERSION }}-${{ github.head_ref || github.ref }}-
    ${{ env.MIX_ENV }}-${{ env.CACHE_VERSION }}-refs/heads/master-
  ```
- **Tool version discovery** via `marocchino/tool-versions-action` (reads `.tool-versions`).
- **Conditional tracker build** using `dorny/paths-filter` to skip tracker rebuild if unchanged.
- **Runner**: Custom `blacksmith-4vcpu-ubuntu-2404` (Blacksmith CI — likely self-hosted or custom).
- **Failure behavior**: `--max-failures 1 --warnings-as-errors`.
- **MinIO service** for S3 integration tests in `test` env:
  ```yaml
  # lines 103-104
  - run: make minio
    if: env.MIX_ENV == 'test'
  ```

**E2E job** runs Playwright tests against the Elixir app with 2 shards. Includes a merge step for blob reports:
```yaml
# lines 236-260 — merge-sharded-e2e-test-report
- run: npx playwright merge-reports --reporter list ../all-e2e-blob-reports
```

**Static checks job** runs:
- `mix format --check-formatted`
- `mix deps.unlock --check-unused`
- `mix generate_countries_meta && git diff --exit-code`
- `mix credo diff --from-git-merge-base origin/master`
- `mix dialyzer`

### 1.2 NPM CI (`node.yml`)

Separate workflow for JS/frontend checks — runs in parallel to Elixir CI. Checks:
- TypeScript type checking
- ESLint + Stylelint
- Prettier format check
- Jest tests
- Tracker script deploy

### 1.3 Build & Publish Images

**Public images** (`build-public-images-ghcr.yml`): Triggered by `v*` tags. Multi-arch build (`linux/amd64` + `linux/arm64`) using matrix strategy with `docker/build-push-action`, pushes digest, then creates a merged manifest list.

**Private images** (`build-private-images-ghcr.yml`): Triggered on `master`/`stable` pushes, `r*` tags, and PRs labeled `preview`. Uses Blacksmith's custom builder action. Notifies team on success/failure via webhook and sets Honeycomb deployment markers.

### 1.4 Tracker Workflows

- **`tracker.yml`**: Runs Playwright tests for the tracker JS script (4 shards) with blob report merging.
- **`tracker-script-update.yml`**: On PRs changing `tracker/src/**`, auto-increments `tracker_script_version` in `package.json`, compiles both master and PR versions, compares script sizes, and enforces release labels.
- **`tracker-script-npm-release.yml`**: On merged PRs with `tracker-release: patch/minor/major` labels, publishes to NPM as `@plausible-analytics/tracker`.

### 1.5 Other Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `all-checks-pass.yml` | PR, merge_group | Uses `poseidon/wait-for-status-checks` as a required gate |
| `codespell.yml` | PR, push master | Spell-check on `lib test extra` |
| `iana-registry-check.yml` | Monthly cron | Verifies IP registry CSVs are up-to-date |
| `migrations-validation.yml` | PR on migration paths | **Prevents lib/ and migrations from being changed in the same PR** |
| `publish-docs.yml` | Push master | Builds `mix docs` and deploys to GitHub Pages |
| `terraform-e2e.yml` | master push + PR on `*.tf` | Validates and applies Checkly Terraform config for E2E monitoring |
| `comment-preview-url.yml` | PR labeled `preview` | Posts preview environment URL |

### 1.6 Dependabot (`dependabot.yml`)

Daily checks for `mix`, `docker`, and `npm` (assets + tracker) ecosystems. Weekly for GitHub Actions. All with 7-day cooldown and `open-pull-requests-limit: 1`.

---

## 2. Docker Build

**File**: `Dockerfile` (87 lines)

### Multi-stage build pattern

**Stage 1 — Builder** (`hexpm/elixir:1.20.2-erlang-28.5.0.3-alpine-3.22.5`):
```dockerfile
# Dockerfile, lines 6-54
FROM hexpm/elixir:1.20.2-erlang-28.5.0.3-alpine-3.22.5@sha256:... AS buildcontainer

ARG MIX_ENV=ce           # default is Community Edition
ENV MIX_ENV=$MIX_ENV
ENV NODE_ENV=production
ENV NODE_OPTIONS=--openssl-legacy-provider

ARG ERL_FLAGS            # for multi-platform QEMU fix
ENV ERL_FLAGS=$ERL_FLAGS
```

Key steps:
1. Install build deps: `git`, `nodejs-current=23.11.1-r0`, `yarn`, `npm`, `python3`, `gcc`, `brotli`
2. Fetch and compile Elixir deps
3. Install npm dependencies for both `assets/` and `tracker/`
4. Build tracker, run `mix assets.deploy`, `mix phx.digest`, `mix download_country_database`, `mix sentry.package_source_code`
5. Run `mix release plausible`

**Stage 2 — Runtime** (`alpine:3.22.5`):
```dockerfile
# Dockerfile, lines 57-86
FROM alpine:3.22.5@sha256:...
LABEL maintainer="plausible.io <hello@plausible.io>"

ARG BUILD_METADATA={}
ENV BUILD_METADATA=$BUILD_METADATA

RUN adduser -S -H -u 999 -G nogroup plausible
RUN apk add --no-cache openssl ncurses libstdc++ libgcc ca-certificates \
  && if [ "$MIX_ENV" = "ce" ]; then apk add --no-cache certbot; fi

COPY --from=buildcontainer --chmod=555 /app/_build/${MIX_ENV}/rel/plausible /app
COPY --chmod=755 ./rel/docker-entrypoint.sh /entrypoint.sh

RUN mkdir -p /var/lib/plausible && chmod ugo+rw -R /var/lib/plausible

USER 999
ENV LISTEN_IP=0.0.0.0
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 8000
ENV DEFAULT_DATA_DIR=/var/lib/plausible
VOLUME /var/lib/plausible
CMD ["run"]
```

Notable:
- `certbot` is only installed in CE (for automatic TLS)
- Volume at `/var/lib/plausible` for persistent data
- Runs as `uid 999` (non-root, but still "others"-accessible for arbitrary UID support)
- **No docker-compose in the repo** — users compose externally

### `.dockerignore`

74 entries excluding build/test artifacts, git history (except `.git/HEAD` for version info), deps, node_modules, static build outputs, geolocation DBs, and local Docker volumes.

---

## 3. Secrets & Environment Variable Management

**File**: `config/runtime.exs` (1107 lines — very large)

### Dual-source strategy: files then env vars

The system reads configuration from a config directory (default `/run/secrets`) first, falling back to environment variables:

```elixir
# lib/plausible/helpers/config.ex, lines 2-10
def get_var_from_path_or_env(config_dir, var_name, default \\ nil) do
  var_path = Path.join(config_dir, var_name)
  if File.exists?(var_path) do
    File.read!(var_path) |> String.trim()
  else
    System.get_env(var_name, default)
  end
end
```

The `config/runtime.exs` uses this pattern for every configuration value:
```elixir
# config/runtime.exs, line 21
config_dir = System.get_env("CONFIG_DIR", "/run/secrets")

# line 81
secret_key_base = get_var_from_path_or_env(config_dir, "SECRET_KEY_BASE", nil)
```

This means secrets can be provided either as:
- **Docker secrets** (files in `/run/secrets/`)
- **Kubernetes secrets** (mounted as files)
- **Environment variables** (plain `ENV`)

### Local development loading

```elixir
# config/runtime.exs, lines 5-18
if config_env() in [:dev, :test, :load] do
  Envy.load(["config/.env.#{config_env()}"])
end
```

Uses the `envy` library to load `.env.dev`, `.env.test` files. These are gitignored.

### Mandatory vs optional variables

**Mandatory** (app will refuse to start without them):
- `BASE_URL`
- `SECRET_KEY_BASE` (min 32 bytes)

**Conditionally mandatory** (raised contextually):
- Geolocation: either `IP_GEOLOCATION_DB` or `MAXMIND_LICENSE_KEY` must be set
- S3: all 6 vars required when `S3_DISABLED` is not `true`
- SMTP auth: both `SMTP_USER_NAME` and `SMTP_USER_PWD` required together

### Key configuration categories

| Category | Env Vars |
|---|---|
| Web server | `LISTEN_IP`, `HTTP_PORT`, `PORT`, `HTTPS_PORT`, `BASE_URL` |
| Auth | `SECRET_KEY_BASE`, `TOTP_VAULT_KEY`, `TOTP_VAULT_KEY_FALLBACK` |
| Database | `DATABASE_URL`, `DATABASE_CACERTFILE`, `CLICKHOUSE_DATABASE_URL` |
| ClickHouse pools | `CLICKHOUSE_INGEST_POOL_SIZE`, `CLICKHOUSE_FLUSH_INTERVAL_MS`, `CLICKHOUSE_MAX_BUFFER_SIZE_BYTES` |
| Mailer | `MAILER_ADAPTER` (6 options), `SMTP_HOST_ADDR`, `POSTMARK_API_KEY`, etc. |
| Error tracking | `SENTRY_DSN`, `SENTRY_FINCH_POOL_TIMEOUT` |
| Observability | `HONEYCOMB_API_KEY`, `HONEYCOMB_DATASET`, `OTLP_ENDPOINT`, `BEAM_METRICS_ENABLED` |
| Billing | `PADDLE_VENDOR_AUTH_CODE`, `PADDLE_VENDOR_ID` |
| Geo | `IP_GEOLOCATION_DB`, `MAXMIND_LICENSE_KEY`, `MAXMIND_EDITION` |
| Features | `DISABLE_REGISTRATION`, `ENABLE_EMAIL_VERIFICATION`, `SELFHOST` |
| HTTPS (CE) | `HTTPS_PORT`, `ACME_DIRECTORY_URL` |
| S3 | `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY`, `S3_ENDPOINT`, etc. |
| Rate limiting | `ADMIN_USER_IDS` |

### Build metadata

```elixir
# config/runtime.exs, lines 242-250
runtime_metadata = [
  version: get_in(build_metadata, ["labels", "org.opencontainers.image.version"]),
  commit: get_in(build_metadata, ["labels", "org.opencontainers.image.revision"]),
  created: get_in(build_metadata, ["labels", "org.opencontainers.image.created"]),
  tags: get_in(build_metadata, ["tags"]),
  app_host: app_host
]
config :plausible, :runtime_metadata, runtime_metadata
```

The `BUILD_METADATA` env var is a JSON string passed during Docker build, containing OCI labels.

---

## 4. Configuration Organization

### Environment split

The app has **7 environments**:
| Env | Purpose | Imports |
|---|---|---|
| `dev` | Local development | — |
| `test` | Unit tests | — |
| `prod` | EE production | — |
| `ce` | CE production | `prod.exs` |
| `ce_dev` | CE development | `dev.exs` |
| `ce_test` | CE tests | `test.exs` |
| `e2e_test` | End-to-end tests | — |
| `load` | Load testing/benchmark | — |

### Config file hierarchy

```
config.exs                    # Base config (shared across all envs)
  └─ import_config "#{config_env()}.exs"
       ├── dev.exs            # Phoenix watchers, debug settings, mock APIs
       ├── test.exs           # Sandbox pool, mock APIs, test-specific settings
       ├── prod.exs           # Static manifest, server: true
       ├── ce.exs             # Imports prod.exs + Brotli/Gzip compression, rate limits
       ├── ce_dev.exs         # Imports dev.exs + CE-specific esbuild
       ├── ce_test.exs        # Imports test.exs
       ├── e2e_test.exs       # Server mode, mock APIs
       └── load.exs           # High-concurrency HTTP settings
runtime.exs                   # Runtime evaluation (reads env/files)
```

### Key `config.exs` settings (base)

```elixir
# config/config.exs, lines 19-26
config :esbuild,
  version: "0.17.11",
  default: [
    args: ~w(js/app.js ... --bundle --target=es2017 --loader:.js=jsx --outdir=../priv/static/js --define:BUILD_EXTRA=true),
    cd: Path.expand("../assets", __DIR__),
  ]

config :tailwind, version: "4.1.12"  # Tailwind v4
```

### CE vs EE split pattern

Uses `Plausible` module macros (`on_ee`, `on_ce`) extensively in application code. In config, CE configs are separate `ce_*` files. The `ce.exs` imports `prod.exs` then overrides:
- Adds `PhoenixBakery.Gzip` and `PhoenixBakery.Brotli` compressors
- Sets `BUILD_EXTRA=false` for esbuild (excludes EE-only dashboard features)
- Sets much higher API rate limits (1 million vs 600/hour)

---

## 5. Deployment & Releases

### Release config in `mix.exs`

```elixir
# mix.exs, lines 20-28
releases: [
  plausible: [
    include_executables_for: [:unix],
    config_providers: [
      {Config.Reader,
       path: {:system, "RELEASE_ROOT", "/import_extra_config.exs"}, imports: []}
    ]
  ]
]
```

This allows adding extra config at release runtime via `import_extra_config.exs`.

### Release overlays in `rel/overlays/`

A set of shell scripts for database operations — invoking `Plausible.Release` module functions via `eval`:

| Script | Calls | Purpose |
|---|---|---|
| `migrate.sh` | `Plausible.Release.interweave_migrate` | Custom multi-repo migration |
| `seed.sh` | `Plausible.Release.seed` | Run seed scripts |
| `rollback.sh` | `Plausible.Release.rollback` | Interactive rollback |
| `createdb.sh` | `Plausible.Release.createdb` | Create databases |
| `pending-migrations.sh` | `Plausible.Release.pending_streaks` | List pending migrations |

### `import_extra_config.exs`

```elixir
# rel/overlays/import_extra_config.exs, lines 1-8
import Config
import Plausible.ConfigHelpers

config_dir = System.get_env("CONFIG_DIR", "/run/secrets")
if extra_config_path = get_var_from_path_or_env(config_dir, "EXTRA_CONFIG_PATH") do
  import_config extra_config_path
end
```

Allows injecting additional config via `EXTRA_CONFIG_PATH` env/secret at deployment time.

### Docker entrypoint

```bash
# rel/docker-entrypoint.sh
#!/bin/sh
set -e
if [ "$1" = 'run' ]; then
      exec /app/bin/plausible start
elif [ "$1" = 'db' ]; then
      exec /app/"$2".sh   # e.g., `docker run image db migrate`
else
      exec "$@"
fi
```

### VM args

```erlang
# rel/vm.args.eex
<%= if Application.get_env(:plausible, :is_selfhost) != true do %>
-kernel inet_dist_listen_min 9100
-kernel inet_dist_listen_max 9200
<% end %>
+Mdai max       # Max dirty scheduler threads
```

### Release scripts (build tooling)

**`rel/prepare_release.sh`** — writes `priv/version.json` with version and commit SHA.

**`rel/release_selfhosted.sh`** — guides building and pushing multi-tag Docker images (`plausible/analytics:vX.Y.Z`, `:vX.Y`, `:vX`, `:latest`). Currently commented out — serves as documentation.

---

## 6. Clustering (libcluster)

**Dependency**: `{:libcluster, "~> 3.5"}` in `mix.exs` (line 181).

**Configured only in EE** via `on_ee` macro in the supervision tree:

```elixir
# lib/plausible/application.ex, lines 14-27
cluster =
  on_ee(
    do:
      {Cluster.Supervisor,
       [
         [
           default: [
             strategy: Cluster.Strategy.ErlangHosts,
             config: [timeout: 30_000]
           ]
         ],
         [name: Plausible.ClusterSupervisor]
       ]}
  )
```

**Strategy**: `Cluster.Strategy.ErlangHosts` — nodes discover each other via the `.hosts.erlang` file. Timeout of 30 seconds.

**CE has no clustering** — the `cluster` variable becomes `nil` in CE and is filtered out:
```elixir
# line 210
|> Enum.reject(&is_nil/1)
```

**Distribution ports** (`inet_dist_listen_min/max`) configured only for non-selfhost (EE) in `vm.args.eex`.

---

## 7. Reverse Proxy & TLS

**No nginx/Caddy/Traefik configs in the repository.** Plausible handles TLS directly in CE via `site_encrypt` (Let's Encrypt integration).

### CE HTTPS with automatic ACME

```elixir
# lib/plausible/application.ex, lines 408-425
on_ce do
  defp maybe_https_endpoint do
    endpoint_config = Application.fetch_env!(:plausible, PlausibleWeb.Endpoint)
    selfhost_config = Application.fetch_env!(:plausible, :selfhost)
    site_encrypt_config = Keyword.get(selfhost_config, :site_encrypt)

    if get_in(endpoint_config, [:https, :port]) do
      PlausibleWeb.Endpoint.force_https()
    end

    if site_encrypt_config do
      PlausibleWeb.Endpoint.allow_acme_challenges()
      {SiteEncrypt.Phoenix.Endpoint, endpoint: PlausibleWeb.Endpoint}
    else
      PlausibleWeb.Endpoint
    end
  end
end
```

When `HTTPS_PORT` is set in CE, it:
1. Configures TLS with Mozilla intermediate-compatible ciphers (ECDHE-only)
2. Sets up ACME via `SiteEncrypt` (Let's Encrypt)
3. Validates domain (no IPs or localhost for TLS)
4. Warns if HTTP port is not 80 (required for ACME validation)

```elixir
# config/runtime.exs, lines 411-431
https_opts = [
  port: https_port,
  ip: listen_ip,
  versions: [:"tlsv1.2", :"tlsv1.3"],
  honor_cipher_order: true,
  honor_ecc_order: true,
  eccs: [:x25519, :secp256r1, :secp384r1],
  ciphers: [
    ~c"TLS_AES_128_GCM_SHA256",
    ~c"TLS_AES_256_GCM_SHA384",
    ~c"TLS_CHACHA20_POLY1305_SHA256",
    ~c"ECDHE-ECDSA-AES128-GCM-SHA256",
    ~c"ECDHE-ECDSA-AES256-GCM-SHA384",
    ~c"ECDHE-ECDSA-CHACHA20-POLY1305"
  ]
]
```

### Phoenix Endpoint defaults

```elixir
# config/config.exs, lines 6-14
config :plausible, PlausibleWeb.Endpoint,
  live_view: [signing_salt: "f+bZg/crMtgjZJJY7X6OwIWc3XJR2C5Y"],
  pubsub_server: Plausible.PubSub,
  render_errors: [
    view: PlausibleWeb.ErrorView,
    layout: {PlausibleWeb.LayoutView, "base_error.html"},
    accepts: ~w(html json)
  ]
```

### E2E monitoring via Checkly (Terraform)

**File**: `test/e2e/main.tf` (363 lines)

Uses Checkly to monitor production endpoints from 7 global locations:
- `/api/health` (asserts clickhouse, postgres, sites_cache are "ok")
- `/api/event` (ingestion endpoint, asserts 202 + no dropped header)
- `/js/script.js` (tracker script, asserts `window.plausible` is present)
- Websocket and LB health endpoints

Alerts go to PagerDuty and Instatus status page.

---

## 8. CI Checks (Static Analysis & Linting)

### Elixir checks

**Format**: `mix format --check-formatted` (pre-commit hooks too).

**Credo** (`.credo.exs` — 210 lines): Standard config with max line length 120, strict mode off, 5s parse timeout. Notable:
- `CyclomaticComplexity` explicitly disabled
- `MaxLineLength` at low priority
- 32 enabled checks, ~30 disabled (opt-in)

**Dialyzer** (`.dialyzer_ignore.exs` — 6 lines): Only 4 ignored warnings — very clean codebase.

**Deps**: `mix deps.unlock --check-unused` ensures no unused dependencies.

**Generated files check**: `mix generate_countries_meta && git diff --exit-code` ensures generated files are committed.

**Compilation**: `--warnings-as-errors --all-warnings` — zero tolerance.

### Pre-commit hooks (`.pre-commit-config.yaml`)

```yaml
repos:
  - repo: https://gitlab.com/jvenom/elixir-pre-commit-hooks
    rev: v1.0.0
    hooks:
      - id: mix-format
  - repo: https://github.com/pre-precommit/pre-commit-hooks
    rev: v4.0.1
    hooks:
      - id: check-case-conflict
      - id: check-yaml
      - id: end-of-file-fixer
      - id: trailing-whitespace
```

Simple — just formatter and basic file checks.

### Asset/frontend checks

- TypeScript type checking (`tsc --noEmit`)
- ESLint + Stylelint
- Prettier format check
- Jest tests (with jsdom)
- Generated type validation: `npm run generate-types && git diff --exit-code`

### Migration validation

A dedicated workflow (`migrations-validation.yml`) **prevents lib/ and migration changes in the same PR**:

```yaml
# .github/workflows/migrations-validation.yml, lines 30-32
- if: steps.changes.outputs.lib == 'true' || steps.changes.outputs.extra == 'true' || steps.changes.outputs.config == 'true'
  run: |
    echo "::error ...::Code and migrations shouldn't be changed at the same time"
    exit 1
```

---

## 9. Database — Multi-Repo Migrations

### Repositories

Defined in `config.exs`:
```elixir
# config/config.exs, line 4
config :plausible, ecto_repos: [Plausible.Repo, Plausible.IngestRepo]
```

**Four ClickHouse repos** used in practice:
| Repo | Purpose |
|---|---|
| `Plausible.Repo` | PostgreSQL (primary app data) |
| `Plausible.ClickhouseRepo` | ClickHouse (analytics reads) |
| `Plausible.IngestRepo` | ClickHouse (event ingestion writes) |
| `Plausible.AsyncInsertRepo` | ClickHouse (async writes) |
| `Plausible.ImportDeletionRepo` | ClickHouse (import deletions) |

### Migration count

- **`priv/repo/migrations/`**: ~233 migration files (PostgreSQL — dates from 2018)
- **`priv/ingest_repo/migrations/`**: ~56 migration files (ClickHouse — dates from 2020)

### Interweaved migration strategy

The custom `Plausible.Release.interweave_migrate/0` function solves a cross-repo migration ordering problem:

```elixir
# lib/plausible_release.ex, lines 63-75
def interweave_migrate(repos \\ repos()) do
  prepare()
  pending = all_pending_migrations(repos)
  streaks = migration_streaks(pending)

  Enum.each(streaks, fn {repo, up_to_version} ->
    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, to: up_to_version),
        log: :notice
      )
  end)
end
```

Instead of running all PG migrations then all CH migrations (which would fail when PG migrations depend on CH schema changes), it sorts all pending migrations by timestamp and groups consecutive migrations from the same repo into "streaks", executing them in chronological order.

### Pool configuration

PostgreSQL:
```elixir
# config/config.exs, lines 62-67
config :plausible, Plausible.Repo,
  timeout: 300_000,
  connect_timeout: 300_000,
  handshake_timeout: 300_000,
  queue_target: 500,
  queue_inerval: 1100
```

ClickHouse:
```elixir
# config/runtime.exs, lines 650-700
config :plausible, Plausible.ClickhouseRepo,
  queue_target: 500,
  queue_interval: 2000,
  timeout: 15_000,
  settings: [
    readonly: 1,
    join_algorithm: "direct,parallel_hash,hash",
    cancel_http_readonly_queries_on_client_close: 1,
    max_execution_time: 20
  ]

config :plausible, Plausible.IngestRepo,
  queue_target: 500,
  queue_interval: 2000,
  flush_interval_ms: ch_flush_interval_ms,   # default 5000ms
  max_buffer_size: ch_max_buffer_size,        # default 100000 bytes
  pool_size: ingest_pool_size,                # default 5
  settings: [materialized_views_ignore_errors: 1],
  table_settings: [storage_policy: ...]
```

IngestRepo uses a separate pool with buffering/flushing. SSL options support CA cert files for ClickHouse connections.

### Database SSL support

PostgreSQL SSL modes supported: `disable`, `require`, `verify-ca`, `verify-full` — configurable via `DATABASE_URL` query parameters with CA cert file support.

### Seed data

Standard Ecto seeds at `priv/repo/seeds.exs` and `priv/ingest_repo/seeds.exs`.

---

## 10. Asset Pipeline

### esbuild

```elixir
# config/config.exs, lines 19-26
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js js/dashboard.tsx js/embed.host.js js/embed.content.js --bundle --target=es2017 --loader:.js=jsx --outdir=../priv/static/js --define:BUILD_EXTRA=true),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]
```

Four entry points: main app (React), dashboard, and two embeds. `BUILD_EXTRA` flag gates EE-only features.

### Tailwind CSS v4

```elixir
# config/config.exs, lines 28-36
config :tailwind,
  version: "4.1.12",
  default: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]
```

### Mix aliases for assets

```elixir
# mix.exs, lines 208-218
"assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
"assets.build": ["tailwind default", "esbuild default"],
"assets.deploy": [
  "tailwind default --minify",
  "esbuild default --minify",
  "phx.digest"
]
```

### Frontend stack

- **React 18** (not Svelte) with TypeScript
- **React Router v6** for client-side routing
- **TanStack React Query** for data fetching
- **Chart.js + D3** for visualizations
- **Headless UI + Heroicons** for UI components
- **Alpine.js** for lightweight interactivity
- **Jest + Testing Library** for frontend tests

### Tracker script

Separate npm package in `tracker/` — compiled to vanilla JS via a custom `compile.js` script. Published to NPM as `@plausible-analytics/tracker`. Has its own Playwright test suite (4 shards).

### CE vs EE asset differences

CE builds with `--define:BUILD_EXTRA=false`, which disables EE-specific dashboard features. CE also uses Brotli/Gzip pre-compression via `PhoenixBakery`.

---

## Summary of Key Patterns

| Aspect | Pattern Used |
|---|---|
| **CI parallelism** | Matrix builds (6 partitions), separate JS workflow, workflow concurrency groups |
| **Cache strategy** | Cache versioned (v18), branch-aware key with master fallback |
| **Secrets** | File-based (`/run/secrets/`) with env var fallback — agnostic to deployment platform |
| **Config** | Runtime evaluation via `runtime.exs`, CE/EE split via separate env files |
| **Docker** | Multi-stage (builder + runtime slim), ARG-driven CE/EE selection |
| **Migrations** | Custom interweaved strategy for multi-repo (Postgres + ClickHouse) |
| **Clustering** | EE-only via libcluster/ErlangHosts with 30s timeout |
| **TLS** | Built-in via site_encrypt (Let's Encrypt), no external proxy |
| **Observability** | OpenTelemetry (Honeycomb), Sentry, PromEx (Prometheus), BEAM metrics opt-in |
| **Job scheduling** | Oban with cron plugins, Postgres peer for leader election |
| **Monitoring** | Checkly (Terraform-managed) from 7 global locations, alerts to PagerDuty + Instatus |
