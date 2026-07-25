# Logflare Infrastructure & CI/CD Report

Logflare is a log ingestion and management platform (by Supabase) written in Elixir/Phoenix.  
It runs on **GCP**, uses **GitHub Actions** + **Cloud Build** for CI/CD, and is **Docker-based** with a
multi-stage build strategy that pre-caches dependencies into base/runner images.

---

## 1. GitHub Actions Workflows

**12 workflows** in `.github/workflows/`:

| Workflow file | Trigger | Purpose |
|---|---|---|
| `elixir-ci.yml` | push main, PR any | Core CI: credo, formatting, tests, dialyzer, frontend tests |
| `docker-ci-amd-and-arm.yml` | push main | Builds multi-arch Docker images (amd64 + arm64) on Blacksmith runners, pushes to DockerHub |
| `docker-test.yml` | PR main, Docker paths | Verifies Docker build succeeds (no push) |
| `docker-base-runner-daily.yml` | daily cron, workflow_dispatch | Rebuilds `supabase/logflare:base` and `:runner` images |
| `docker-retag-versioned.yml` | workflow_dispatch | Retags dev image → versioned tag, mirrors to ECR + GHCR |
| `trigger-cloudbuild.yml` | workflow_call | Shared workflow: deploys prod/staging via Cloud Build |
| `elixir-migration-check.yml` | PR on migrations | Tests migrations forward + rollback |
| `e2e-tests.yml` | PR, weekly cron | Playwright E2E tests (headless) |
| `integration-supabase.yml` | push/PR main | Full Supabase integration tests with Playwright in Chrome/Firefox/Safari |
| `pages.yml` | push main (docs/) | Deploys docs site to GitHub Pages |
| `pages-build.yml` | PR (docs/) | Checks docs build |
| `pr-management.yml` | PR opened/reopened | Auto-assigns PR author |

### Key patterns

**Version parsing** — many workflows use `.tool-versions` as single source of truth:

```yaml
# .github/workflows/elixir-ci.yml, lines 33-45
- name: Read versions from .tool-versions
  id: v
  run: |
    echo "elixir=$(grep '^elixir '  .tool-versions | awk '{print $2}')" >> "$GITHUB_OUTPUT"
    echo "erlang=$(grep '^erlang '  .tool-versions | awk '{print $2}')" >> "$GITHUB_OUTPUT"
    echo "rust=$(grep   '^rust '    .tool-versions | awk '{print $2}')" >> "$GITHUB_OUTPUT"
```

**Caching strategy** — three separate cache keys:

```yaml
# .github/workflows/elixir-ci.yml, lines 132-163
- name: Restore Cargo cache       # ~/.cargo + target
- name: Restore Mix cache          # deps, _build, priv/native
- name: Restore Dialyzer PLT cache # dialyzer/
```

Uses `actions/cache@v5` with versioned keys (`mix-v3-`), restoring from broader fallback keys.

**Matrix for CI checks** — single job matrix running 5 different commands:

```yaml
# .github/workflows/elixir-ci.yml, lines 51-66
matrix:
  commands:
    - name: Code Quality - Linting          # mix lint.all (credo --strict)
    - name: Code Quality - Formatting        # mix test.format
    - name: Compilation Warnings             # mix test.compile
    - name: Tests                            # mix test.coverage.ci (coveralls)
    - name: Typing check                     # mix test.typings (dialyzer)
```

**Service containers** — both `elixir-ci.yml` and `e2e-tests.yml` spin up:

- `bitnamilegacy/postgresql:15` with WAL level `logical` (for Postgres LISTEN/NOTIFY clustering)
- `clickhouse/clickhouse-server:26.2` with resource limits (1.5GB mem, 1 CPU, tmpfs)

**Multi-arch Docker CI** — `docker-ci-amd-and-arm.yml` builds on **Blacksmith** runners (4vCPU, separate amd64/arm64 VMs), then merges manifests:

```yaml
# .github/workflows/docker-ci-amd-and-arm.yml, lines 27-32
matrix:
  include:
    - runner: blacksmith-4vcpu-ubuntu-2404
      arch: amd64
    - runner: blacksmith-4vcpu-ubuntu-2404-arm
      arch: arm64
```

**Image mirroring** — `docker-retag-versioned.yml` pushes to three registries:

```yaml
# .github/workflows/docker-retag-versioned.yml, lines 88-98
SOURCE_IMAGE=docker.io/supabase/logflare:$VERSION
ECR_IMAGE=public.ecr.aws/supabase/logflare:$VERSION
GHCR_IMAGE=ghcr.io/supabase/logflare:$VERSION
docker buildx imagetools create --prefer-index=false \
  -t "$ECR_IMAGE" -t "$GHCR_IMAGE" "$SOURCE_IMAGE"
```

---

## 2. Docker — Multi-Stage Build Pipeline

### Image hierarchy

```
Dockerfile.base    →  supabase/logflare:base     (build deps + cargo fetch)
Dockerfile.runner  →  supabase/logflare:runner   (runtime deps only)
                          ↕
Dockerfile.multi-step  →  supabase/logflare:<tag> (FROM base + runner, runs release)
Dockerfile             →  supabase/logflare:<tag> (standalone, no base/runner dependency)
```

### Dockerfile.base (lines 1-49)

Pre-fetches all dependencies in a layer that rarely changes:

```dockerfile
# Lines 16-23: Install build deps (gcc, nodejs, rust)
# Lines 26-30: Mix deps.get + deps.compile
# Lines 32-33: npm ci
# Lines 43-49: Pre-fetch Cargo deps with empty src/lib.rs placeholder
COPY Cargo.toml Cargo.lock ./
COPY --parents native/*/Cargo.toml ./
RUN for dir in native/*/; do mkdir -p "$dir/src" && touch "$dir/src/lib.rs"; done
RUN cargo fetch --locked
```

### Dockerfile.runner (lines 1-16)

Minimal runtime image — just `debian:trixie-slim` + libs + locale:

```dockerfile
RUN apt-get install -y curl libstdc++6 openssl locales
ENV LANG en_US.UTF-8 LC_ALL en_US.UTF-8
```

### Dockerfile.multi-step (lines 1-35)

Uses pre-built `base` and `runner` images, just compiles + releases:

```dockerfile
FROM supabase/logflare:base AS builder
RUN mix release && npm run --prefix assets deploy && mix phx.digest
FROM supabase/logflare:runner
COPY --from=builder /app/_build/prod /opt/app
```

### Dockerfile (standalone, lines 1-81)

All-in-one build for single-stage builds. Notable:

- `ARG COMMIT_SHA` baked in as `ENV LOGFLARE_COMMIT_SHA` (line 65-66) — surfaced as OTel resource attribute
- Static assets are copied from release dir after the fact (lines 71-77)
- `CMD ["sh", "run.sh"]` — runs the custom entrypoint

### run.sh (lines 1-26)

Runtime entrypoint that handles secrets and startup:

```bash
# Load secrets conditionally from file
if [ -f /tmp/.secrets.env ]; then
    export $(grep -v '^#' /tmp/.secrets.env | grep -v '^$' | ... | xargs)
fi

# Optional startup script (e.g. cloudbuild/startup.sh)
if [ -f ./startup.sh ]; then . ./startup.sh; fi

# Run migrations then start
./logflare eval Logflare.Release.migrate
./logflare start --sname logflare
```

### docker-compose.yml (primary, 155 lines)

Single-compose with all services. Key features:

- Uses `hostname: 127.0.0.1` (line 36) for local clustering
- Secrets mounted as bind volumes: `.single_tenant_bq.env` → `/tmp/.secrets.env` (read-only)
- GCP credentials: `gcloud.json` bind-mounted
- Full local dev stack: Postgres, ClickHouse, Grafana, Loki, OTel collector, Telegraf, Filebeat
- ClickHouse uses tmpfs (RAM) — no persistence across restarts (lines 125-128)
- Grafana auto-provisioned with Loki datasource via inline entrypoint (lines 86-104)

### docker-compose.gcp.yml

Runs GCP emulators locally: Fake GCS server + Pub/Sub emulator, auto-creates bucket/topic/subscription via curl.

### docker-compose.minio.yml, docker-compose.pg.yml

Minio S3 + ElasticMQ (SQS) emulators, and a PG-only override that passes `POSTGRES_BACKEND_URL`.

---

## 3. Secrets Management

### Principle: Encrypted files + GCP KMS

Secrets are never in plaintext in the repo. The `cloudbuild/` directory contains `.enc` files:

```
cloudbuild/
  .prod.env.enc              .staging.env.enc
  .prod.gcloud.json.enc      .staging.gcloud.json.enc
  .prod.cert.pem.enc         .staging.cert.pem.enc
  .prod.cert.key.enc         .staging.cert.key.enc
  .prod.db-client-cert.pem.enc  .staging.db-client-cert.pem.enc
  .prod.db-client-key.pem.enc   .staging.db-client-key.pem.enc
  .prod.db-server-ca.pem.enc    .staging.db-server-ca.pem.enc
```

Encrypted via GCP Cloud KMS using distinct keyrings per environment:

```
Staging: logflare-keyring-us-central1 / logflare-secrets-key
Prod:    logflare-prod-keyring-us-central1 / logflare-prod-secrets-key
```

### Makefile targets for encryption

```makefile
# Makefile, lines 200-255
# Generic pattern: cloudbuild/*.enc → plaintext via gcloud kms decrypt
%: cloudbuild/%.enc
    @gcloud kms decrypt --ciphertext-file=$< --plaintext-file=$@ \
        --location=${GCLOUD_LOCATION} --keyring=${GCLOUD_KEYRING} \
        --key=${GCLOUD_KEY} --project=${GCLOUD_PROJECT}

# Staging and prod use separate keyrings (lines 231-233)
%crypt.prod: GCLOUD_KEYRING = logflare-prod-keyring-us-central1
%crypt.prod: GCLOUD_KEY = logflare-prod-secrets-key
%crypt.prod: GCLOUD_PROJECT = logflare-232118
```

### Runtime secret loading

The `run.sh` script loads secrets from `/tmp/.secrets.env` at container start. The Dockerfile mounts this file (docker-compose.yml line 40). The deploy pipeline builds a `secret_setup.Dockerfile` that copies the decrypted secrets into the final image.

### CI secrets

GitHub Actions secrets used:
- `DOCKERHUB_USERNAME` + `DOCKERHUB_TOKEN` — for pushing to DockerHub
- `GCP_PROD_CREDENTIALS` + `GCP_STAGING_CREDENTIALS` — for gcloud auth in `trigger-cloudbuild.yml`
- `PROD_AWS_ROLE` — for ECR mirroring
- `IMAGE_PUSH_GH_PRIVATE_KEY` + `IMAGE_PUSH_GH_CLIENT_ID` — for GHCR auth

### .template.env (lines 1-56)

Documents **all** env vars the app accepts. This is the single source of truth — includes OAuth, Stripe, GCP, Vercel, OTel, mailer, Twilio config.

---

## 4. Configuration Architecture

### Standard Elixir compile-time configs

| File | Purpose |
|---|---|
| `config/config.exs` | Base config — encryption keys, endpoint defaults, logger, OAuth, Oban, OpenTelemetry (disabled by default), libcluster defaults |
| `config/dev.exs` | Dev-specific — debug errors, live reload, local GCP emulators, local Postgres, Vercel OAuth dev creds, S3/SQS via MinIO/ElasticMQ |
| `config/test.exs` | Test-specific — Sandbox pool, SQL sandbox, logger filters for Finch/DB noise, Oban manual mode |
| `config/prod.exs` | Production — server: true, cache manifest, spool defaults (mode: :disable, :etf format) |
| `config/docker.exs` | Docker dev mode — supabase_mode: true, no code reloader |

### Runtime config (`config/runtime.exs`, 586 lines)

All runtime-configurable values use `System.get_env/2` with nil-coalescing via a `filter_nil_kv_pairs` helper:

```elixir
# config/runtime.exs, lines 30-32
filter_nil_kv_pairs = fn pairs when is_list(pairs) ->
  Enum.filter(pairs, fn {_k, v} -> v !== nil end)
end
```

Key runtime-configurable blocks:

| Block (line) | Env vars | Purpose |
|---|---|---|
| Endpoint (108-142) | `PHX_HTTP_PORT`, `PHX_HTTP_IP`, `PHX_URL_HOST`, etc. | Web server binding |
| Repo (144-172) | `DB_DATABASE`, `DB_HOSTNAME`, `DB_PASSWORD`, `DB_PORT`, `DB_SSL`, `DB_SCHEMA` | Postgres connection |
| Logger (198-209) | `LOGFLARE_LOG_LEVEL` | Log level at runtime |
| OAuth (243-262) | `UEBERAUTH_*_CLIENT_ID/SECRET` | GitHub, Google, Slack OAuth |
| Stripe (276-284) | `STRIPE_API_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET` | Billing |
| OpenTelemetry (424-477) | `LOGFLARE_OTEL_ENDPOINT`, `LOGFLARE_OTEL_SAMPLE_RATIO`, etc. | Tracing |
| DB SSL (355-387) | `DB_SSL`, `DB_SSL_CA_CERT_PATH`, `DB_SSL_CLIENT_CERT_PATH`, `DB_SSL_CLIENT_KEY_PATH` | mTLS for Postgres |
| Cache gossip (505-537) | `LOGFLARE_CACHE_GOSSIP_ENABLED`, `LOGFLARE_CACHE_GOSSIP_RATIO`, `LOGFLARE_CACHE_GOSSIP_MAX_NODES` | Distributed cache invalidation |
| Read replicas (539-549) | `LOGFLARE_READ_REPLICAS` | Comma-separated replica hosts |
| Spool mode (551-586) | `SPOOL_MODE`, `SPOOL_PROVIDER`, `SPOOL_QUEUE_NAME`, etc. | Log spooling overrides |
| Feature flags (389-403) | `LOGFLARE_FEATURE_FLAG_OVERRIDE` | Comma-separated key=value overrides |

### Erlang VM tuning (`rel/vm.args.eex`, lines 1-47)

```erlang
+sbwt none                     % No busy-wait for schedulers
+sub true                      % Utilization-based load balancing
+swt very_low                  % Wake-up threshold
+zdbbl 1028000                 % Distribution buffer limit
+P 8000000                     % Max processes
+t 32000000                    % Max atom table
+Mdai max                      % Dirty allocator instances
-kernel net_ticktime 45        % Faster node disconnect detection
-kernel prevent_overlapping_partitions false
```

### Release node naming (`rel/env.sh.eex`, lines 1-20)

```bash
export RELEASE_DISTRIBUTION=name
HOST="${LOGFLARE_NODE_HOST:-127.0.0.1}"
CLUSTER_SUFFIX="${LOGFLARE_METADATA_CLUSTER:+-$LOGFLARE_METADATA_CLUSTER}"
export RELEASE_NODE="logflare$CLUSTER_SUFFIX@$HOST"
```

---

## 5. Deployment — GCP Cloud Build

### Architecture

```
GitHub → DockerHub (multi-arch image) → Cloud Build (decrypt secrets, build sealed image)
       → Instance Template (cos-stable container) → Managed Instance Group (rolling update)
```

### Cloud Build configs

**Staging** (`cloudbuild/staging/`):
- `build-image.yaml` — Decrypts 7 files via KMS → builds `secret_setup.Dockerfile` → pushes to `gcr.io/logflare-staging/logflare_app`
- `deploy.yaml` — Creates `instance-templates create-with-container`, then `instance-groups managed rolling-action start-update`

**Prod** (`cloudbuild/prod/`):
- `build-image.yaml` — Same pattern, pushes to `gcr.io/logflare-232118/logflare_app`
- `pre-deploy.yaml` — Creates instance template with container env vars (per-cluster)
- `deploy.yaml` — Rolling update on managed instance groups

### Deploy sequence (from Makefile, lines 286-383)

Staging main deploy:
```makefile
# Three sequential Cloud Build submissions:
gcloud builds submit . --config=cloudbuild/staging/build-image.yaml
gcloud builds submit . --config=cloudbuild/staging/deploy.yaml   # c2d-standard-16
gcloud builds submit . --config=cloudbuild/staging/deploy.yaml   # c2d-highcpu-16 (saturated)
```

Prod versioned deploy:
```makefile
# 1. Build image
# 2. Canary pre-deploy + deploy
# 3. Six prod clusters (prod-a through prod-g):
#    - prod-a: LOGFLARE_ALERTS_ENABLED=true
#    - prod-b..prod-f: LOGFLARE_ALERTS_ENABLED=false
#    - prod-g: (no alerts override)
```

### Instance template settings (from `cloudbuild/staging/deploy.yaml`)

```yaml
- --machine-type=${_INSTANCE_TYPE}           # c2d-highcpu-4 / c2d-standard-16 / c2d-highcpu-16
- --maintenance-policy=TERMINATE
- --service-account=compute-engine-2022@...
- --tags=phoenix-http,https-server
- --metadata-from-file=shutdown-script=./cloudbuild/shutdown.sh
- --container-privileged
- --container-restart-policy=always
- --container-env=LOGFLARE_GRPC_PORT=50051,RELEASE_COOKIE=${_COOKIE},LOGFLARE_METADATA_CLUSTER=${_CLUSTER}
- --image=cos-stable-109-17800-147-54        # Container-Optimized OS
```

### Startup / shutdown scripts

**startup.sh** (lines 1-19):
```bash
# Wait 15s for GCE networking
sysctl -w net.ipv4.tcp_keepalive_time=60 ...
export LOGFLARE_NODE_HOST=$(curl -s "http://metadata.google.internal/..." -H "Metadata-Flavor: Google")
```

**shutdown.sh** (lines 1-24):
```bash
# Notify Logflare API of shutdown
curl -X POST "https://api.logflarestaging.com/api/logs?..."
# Hit local shutdown endpoint with token
curl -X PUT "http://localhost:4000/admin/shutdown?code=$LOGFLARE_NODE_SHUTDOWN_CODE"
sleep 20
```

---

## 6. Clustering

### libcluster with custom Postgres strategy

Logflare uses `libcluster` with a **custom `Cluster.PostgresStrategy`** instead of the built-in GKE/Kubernetes strategies.

**Configuration** (`config/runtime.exs`, lines 411-422):

```elixir
postgres_topology = [
  postgres: [
    strategy: Logflare.Cluster.PostgresStrategy,
    config: [release_name: :logflare]
  ]
]

config :libcluster,
  topologies:
    if(System.get_env("LIBCLUSTER_TOPOLOGY") == "postgres", do: postgres_topology, else: [])
```

**Custom strategy** (`lib/logflare/cluster/postgres_strategy.ex`, 131 lines):

Uses Postgres `LISTEN/NOTIFY` for node discovery:

```elixir
# Heartbeat: every 5 seconds, NOTIFY the channel with current node name
P.query(conn, "NOTIFY cluster_#{cookie}, '#{node()}'", [])

# Listener: on notification, connect to new nodes
def handle_info({:notification, _pid, _ref, _channel, node_str}, state) do
  node = String.to_atom(node_str)
  if node != node() and node not in Node.list() do
    Strategy.connect_nodes(topology, state.connect, state.list_nodes, [node])
  end
end
```

The channel is derived from the Erlang cookie: `"cluster_" <> clean_cookie(Node.get_cookie())`.

### Dev clustering

The Makefile supports running multiple nodes locally:
```makefile
start.orange: ERL_NAME = orange   # PORT=4000
start.pink:   ERL_NAME = pink     # PORT=4001
start.green:  ERL_NAME = green    # PORT=4002, ERL_COOKIE=greenmonster
```

Each node uses a unique `--sname` and port but shares the database for cluster discovery.

### Cache gossip

In addition to node clustering, Logflare has a **cache gossip** system (`config/runtime.exs`, lines 505-537):
- Configurable ratio of nodes to gossip to (default 5%)
- Max nodes to gossip to (default 3)
- Enabled by default in test, disabled in production unless explicitly set

---

## 7. Reverse Proxy

There is **no nginx/caddy/haproxy config** in the repo. GCP handles load balancing:

1. **GCP External HTTPS Load Balancer** — terminates TLS, forwards to backend services
2. **Managed Instance Groups** — auto-scaling groups behind the LB
3. The `config/config.exs` endpoint settings reference GCP LB behavior:
   ```elixir
   # Lines 52-53: Backend keepalive timeout
   read_timeout: 620_000,  # 620s > GCP LB's 600s timeout
   ```
4. Container-Optimized OS with `cos-stable` image plus HTTP server tags: `--tags=phoenix-http,https-server`

---

## 8. CI Checks

### Executed via mix aliases (`mix.exs`, lines 271-291)

| Alias | Tool | Mix command |
|---|---|---|
| `lint.all` | Credo (strict) | `mix credo --strict` |
| `test.format` | Formatter | `mix format --check-formatted` |
| `test.compile` | Compiler warnings | `mix compile --warnings-as-errors` |
| `test.security` | Sobelow | `mix sobelow --threshold high --ignore Config.HTTPS` |
| `test.typings` | Dialyzer | `mix dialyzer` |
| `test.coverage.ci` | ExCoveralls | `mix coveralls.github` |

### Credo config (`config/.credo.exs`, 188 lines)

- Max line length: 120
- All standard checks enabled (consistency, design, readability, refactoring, warnings)
- Controversial/experimental checks disabled (CyclomaticComplexity, ModuleDoc, etc.)
- `mix lint.all` runs `--strict` mode

### Dialyzer config (`mix.exs`, lines 70-78)

```elixir
defp dialyzer do
  [
    plt_local_path: "dialyzer",
    plt_core_path: "dialyzer",
    plt_add_deps: :apps_tree,
    plt_add_apps: [:ex_unit, :mix],
    ignore_warnings: ".dialyzer_ignore.exs"
  ]
end
```

`.dialyzer_ignore.exs` — 54 entries suppressing known warnings (pattern matches, return types, unused functions).

### Coveralls (`coveralls.json`)

```json
{
  "coverage_options": { "minimum_coverage": 80 },
  "skip_files": ["test", "lib/mix"]
}
```

Minimum 80% coverage enforced. Excludes `test/` and `lib/mix/` dirs.

### Sobelow

Commented out in CI (line 63-64 of `elixir-ci.yml`):
```yaml
# - name: Security - Sobelow Code Scan
#   run: mix test.security
```
The alias still exists: `mix sobelow --threshold high --ignore Config.HTTPS`.

---

## 9. Database

### Migrations

Located in `priv/repo/migrations/`. The CI (`elixir-migration-check.yml`) tests forward + rollback:

```yaml
- name: Migrate
  run: mix ecto.setup       # create + migrate
- name: Rollback
  run: mix ecto.rollback    # test reversibility
- name: Test
  run: make test.only
```

### Seeds (`priv/repo/seeds.exs`, 228 lines)

Populates billing plans (Free, Hobby monthly/yearly, Pro, Enterprise, Trial). Uses `Logflare.Repo.insert!`.

### Connections

- **Primary**: `Logflare.Repo` — Postgres via `postgrex`, configured with SSL/mTLS support
- **Backend**: Optional Postgres backend via `POSTGRES_BACKEND_URL` for single-tenant mode
- **ClickHouse**: Using `ch` library for log storage
- **BigQuery**: Multiple GCP client libraries (`google_api_big_query`)

---

## 10. Asset Pipeline

### Build tooling

Uses **esbuild** directly (not Phoenix's built-in esbuild wrapper):

```
assets/build.mjs → esbuild + sass + postcss + tailwind
```

Key config (`assets/build.mjs`):

```javascript
entryPoints: ["js/app.js", "js/source.js"],
outdir: "../priv/static/js",          // Output to priv/static
plugins: [sassPostcssPlugin, copyStatic],  // Tailwind via PostCSS + static file copy
minify: watch ? false : true,
```

### Tailwind CSS

Standard Tailwind v3 config at `assets/tailwind.config.js`. PostCSS plugins: `autoprefixer`, `tailwindcss`. The sass plugin runs Tailwind as a PostCSS plugin on `.scss` files.

### Frontend dependencies (`assets/package.json`)

- React 18 + react-dom + react-bootstrap + recharts (charting)
- Phoenix LiveView + LiveReact for hybrid rendering
- Bootstrap 4 + jQuery (legacy)
- Font Awesome, Highlight.js, date-fns, Luxon, Moment
- Playwright + Vitest for testing

### Watcher in dev

`config/dev.exs` runs the asset watcher via Phoenix watchers:

```elixir
watchers: [
  npm: ["run", "watch", cd: Path.expand("../assets", __DIR__),
    env: [{"NODE_ENV", "development"}]]
]
```

### Frontend tests

Run separately in CI (`elixir-ci.yml`, job `frontend`):

```yaml
- name: Install frontend dependencies
  run: npm ci --prefix assets
- name: Run frontend unit tests
  run: npm test --prefix assets
```

---

## Summary of Patterns

| Pattern | Logflare Approach |
|---|---|
| **Single source of truth for versions** | `.tool-versions` file parsed by CI |
| **Docker layer caching** | Separate base/runner images rebuilt daily; multi-step for fast ci |
| **Secrets** | Encrypted at rest via GCP KMS, decrypted in Cloud Build, mounted into container |
| **Multi-arch** | Separate amd64/arm64 VM builds → merged manifests |
| **Image distribution** | DockerHub (primary) → mirrored to public ECR + GHCR |
| **Clustering** | Custom libcluster strategy via Postgres LISTEN/NOTIFY (not k8s) |
| **Deployment target** | GCE Managed Instance Groups (Container-Optimized OS), not k8s |
| **Deploy strategy** | Instance template → rolling update (surge=1, max-unavailable=0) |
| **DB SSL** | mTLS with client certs for Postgres (RFC 6066 SNI-aware) |
| **Telemetry** | OpenTelemetry with custom sampler, gzip HTTP protobuf export |
| **Runtime config** | Single `runtime.exs` consuming env vars with `filter_nil_kv_pairs` helper |
| **Observability** | Grafana + Loki (local), OTel collector, Telegraf metrics, Filebeat log shipping |
