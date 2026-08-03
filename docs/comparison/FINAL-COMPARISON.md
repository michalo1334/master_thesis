# Master Comparison: network_defense vs Community Standards

> Synthesized from 19 report files covering Plausible, Firezone, Logflare, and Livebook across 5 categories.
> Your codebase: `network_defense` (Elixir/Phoenix graph-based attack simulation engine).

---

## 1. Error Handling

### Community Standard

All four projects rely on standard `{:ok, _}` / `{:error, _}` tuples — no dry-monads anywhere.

**Pattern matching on errors:**
- **Plausible**: `with`/`else` chains in controllers, no `action_fallback`. Custom `defstruct` error carriers (`QueryError`, `Non200Error`) instead of `defexception`.
- **Firezone**: `with`/`else` → `Error.handle(conn, error)` pattern. **Bans `action_fallback`** via custom Credo check. Uses `defexception` with `skip_sentry` flags. Follows RFC 9457 for API error responses (`ProblemDetails` module).
- **Logflare**: Central `FallbackController` with pattern-matched clauses for every error type (changeset → 422, buffer_full → 429, not_found → 404, etc.). 12 API controllers use `action_fallback`.
- **Livebook**: Minimal exceptions (5 total) with `plug_status` field for automatic HTTP mapping. Heavy use of Ecto Changesets for validation despite having no database.

**Consensus:** Use `with` chains + centralized error translation. No dry-monads.

### Your Codebase

- Standard Phoenix `ErrorHTML` / `ErrorJSON` with `render_errors` in endpoint config (`src/lib/network_defense_web/controllers/error_json.ex`, `error_html.ex`).
- No `action_fallback` or custom fallback controller.
- No custom error structs or `defexception` types.
- No Sentry error tracking integration.
- No pattern for structured error atoms across domain contexts.

### Gap Analysis

| Gap | Impact |
|-----|--------|
| No centralized error-to-HTTP translation | Ad-hoc error responses, inconsistent JSON shapes |
| No Sentry / error tracking | Blind to production crashes |
| No custom error types | Cannot pattern-match on domain errors |
| No `{:error, :not_found}` conventions across contexts | Inconsistent return types |

### Recommendations

1. **Add a FallbackController** (High) — Create `NetworkDefenseWeb.Api.FallbackController` with pattern-matched clauses for `:not_found`, changeset errors, validation errors. Reference: Logflare's `FallbackController` at `lib/logflare_web/controllers/api/fallback_controller.ex`.

2. **Add Sentry for error tracking** (Critical) — Your app is research software; crashes during batch simulations are invisible. Add `:sentry` dependency, configure in `runtime.exs`, add `Sentry.PlugCapture` to endpoint.

3. **Define domain error atoms** (Medium) — Establish convention: `{:error, :not_found}`, `{:error, :invalid_state}`, `{:error, :simulation_failed}` across all context modules. Reference: Logflare's consistent `fetch_*_by` pattern.

---

## 2. Observability

### Community Standard

| Aspect | Plausible | Firezone | Logflare | Livebook |
|--------|-----------|----------|----------|----------|
| **APM/Tracing** | OTel (Honeycomb) | OTel (Azure) | OTel (custom endpoint) | None |
| **Error tracking** | Sentry | Sentry | None (OpenTelemetry only) | None |
| **Structured logging** | `ex_json_logger` | `logger_json` | `logger_json` (GCP format) | `logger_json` (opt-in) |
| **Metrics** | PromEx (Prometheus) + OTel metrics | OTel metrics + LiveDashboard | OTel metrics + LiveDashboard | LiveDashboard only |
| **Health check** | Postgres + ClickHouse + caches | Postgres + draining + endpoint alive | Postgres + ETS + caches + memory | Static `{"application":"livebook"}` |
| **BEAM metrics** | Top-20 processes (recon) | Full VM metrics (process/atom/port/ETS/GC/scheduler) | Full VM + ETS table monitoring + scheduler util | Minimal (VM memory + run queue) |
| **Custom metrics** | Ingestion pipeline, cache hits, drops | DB query durations, LiveView lifecycle | Broadway pipeline, buffer full, rate limit, 100+ metrics | None (periodic_measurements stubbed) |

**Consensus:** OTel for tracing, structured JSON logging, health checks with real dependency probes, custom business metrics.

### Your Codebase

- OpenTelemetry setup for Bandit, Phoenix, Ecto (`src/lib/network_defense/application.ex` lines 11-13).
- Custom `LoggerJSON` formatter with structured OTP report formatting (`src/lib/network_defense/observability/logger_formatter.ex`).
- Ecto query logging via telemetry handler (`src/lib/network_defense/observability.ex`).
- `TelemetryMetricsPrometheus.Core` for metrics (Phoenix endpoint, DB, VM basic).
- **No Sentry**, **no health check endpoint**, **no custom application metrics** (periodic_measurements is empty).
- LiveDashboard only in dev mode.
- Docker monitoring stack exists (`docker/` with Grafana, Tempo, Loki, Prometheus, Alloy) — but no application-level metrics feeding into it.
- File-based logging to JSONL consumed by Grafana Alloy.

### Gap Analysis

| Gap | Impact |
|-----|--------|
| No health check endpoint | Kubernetes/container orchestration has no way to probe readiness |
| No Sentry error tracking | All production exceptions are invisible |
| No custom business metrics | No visibility into simulation throughput, duration, or failure rates |
| No BEAM process metrics | Can't debug memory leaks or process bottlenecks |
| No trace-log correlation | Log lines don't carry trace IDs for debugging |
| LiveDashboard dev-only | Ops can't inspect system state in production |
| periodic_measurements empty | No data flowing into the existing Prometheus/Grafana stack |

### Recommendations

1. **Add a health check endpoint** (Critical) — Create `GET /health` → `GET /readyz` that probes Postgres and returns 200/503. Reference: Firezone's `lib/portal/health.ex` (95 lines, checks DB + draining + endpoint registration).

2. **Add simulation business metrics** (High) — Implement `:telemetry.execute/3` calls in `Simulator`, `Optimizer`, and `Experiment` modules. Track: simulation duration, Monte Carlo iterations, blast radius per run, defense action counts. Wire these into the existing Prometheus endpoint.

3. **Add trace-log correlation** (Medium) — Inject OTel `trace_id` into Logger metadata at router dispatch (Phoenix telemetry handler). Already have OTel dependency — just need the handler. Reference: Plausible's `Plausible.OpenTelemetry.Logger` (34 lines).

4. **Enable LiveDashboard in production** (Low) — Move behind basic auth. Single line in router. Currently dev-only gated by `Application.compile_env(:network_defense, :dev_routes)`.

5. **Add Oban telemetry** (Medium) — When/if you add Oban for background jobs, instrument with `OpentelemetryOban.setup()`.

---

## 3. Infrastructure & CI/CD

### Community Standard

| Aspect | Plausible | Firezone | Logflare | Livebook |
|--------|-----------|----------|----------|----------|
| **CI workflows** | 14 workflows | 20+ workflows + composite actions | 12 workflows | 2 workflows |
| **CI parallelism** | 6 test partitions, separate JS workflow | Smart diff-based planner (ci.yml) | Matrix (5 commands) | Single job + Windows |
| **Cache** | Versioned mix deps cache (v18) | GHA Docker cache (read-only on PR) | Mix + Cargo + Dialyzer separate caches | Mix + Bun cache |
| **Secrets** | File-based (`/run/secrets`) + env fallback | Env vars + OIDC for Azure | GCP KMS encrypted files | Env vars with validation |
| **Docker** | Multi-stage, ARG-driven CE/EE | Multi-stage with tini | Base/runner image hierarchy | Multi-stage CUDA variant |
| **Static analysis** | Credo, Dialyzer, format, sobelow | Credo, Dialyzer, format, hex.audit, sobelow, OpenAPI validation | Credo strict, Dialyzer, format, sobelow | Format, compile warnings |
| **Coverage** | ExCoveralls (no threshold) | ExCoveralls (Coveralls upload) | ExCoveralls (80% min threshold) | None |
| **Deployment** | Docker images (GHCR), multi-arch | GHCR + Azure Blob + APT/RPM | GCP Cloud Build → MIGs | GHCR + GitHub Releases + Tauri |
| **Clustering** | libcluster (EE only) | libcluster + custom Postgres strategy | libcluster + custom Postgres LISTEN/NOTIFY | Custom EPMD + DNS clustering |
| **Pre-commit** | mix-format + basic hooks | None visible | None visible | None visible |

**Consensus:** CI with linting + tests + coverage, typed env vars, multi-stage Docker, automated releases.

### Your Codebase

- `Dockerfile`: multi-stage build with tini, Node.js for SSR, debian-based.
- Terraform Docker modules: full monitoring stack (Grafana, Tempo, Loki, Prometheus, Alloy).
- `runtime.exs`: secrets from `_FILE` pattern (Docker/K8s compatible), typed env vars.
- `mix precommit` alias: compile warnings, format, credo, dialyzer, sobelow, deps audit, tests.
- **No CI/CD** — zero GitHub Actions workflows, no `.github/` directory.
- **No coverage tracking** — no ExCoveralls in deps.
- **No test partitioning** — `mix test` runs sequentially.
- **No pre-commit hooks** — `mix precommit` exists but is not enforced.

### Gap Analysis

| Gap | Impact |
|-----|--------|
| **No CI** | No automated test runs on push/PR. No guard against regressions. |
| **No coverage tracking** | Can't measure test quality or enforce minimums |
| **No test partitioning** | Test suite will slow as it grows |
| **precommit not enforced** | Developers can accidentally push unformatted/broken code |
| **No .env.example / .template.env** | New contributors must reverse-engineer required env vars |
| **No automated Docker builds** | No regular image builds to catch Dockerfile drift |
| **No dialyzer PLT caching** | Dialyzer runs from scratch every time |

### Recommendations

1. **Add GitHub Actions CI** (Critical) — Create `.github/workflows/ci.yml` that runs on PR/push to main:
   - `mix compile --warnings-as-errors`
   - `mix format --check-formatted`
   - `mix credo`
   - `mix dialyzer`
   - `mix test` with Postgres service container
   - Cache: `deps`, `_build`, `dialyzer/` PLT
   Reference: any of the 4 projects' CI files.

2. **Add ExCoveralls** (High) — Add `{:excoveralls, "~> 0.18", only: :test}` to deps, configure `coveralls.json` with 50-60% minimum (realistic for a research project).

3. **Add test partitioning** (Medium) — `mix test` supports `MIX_TEST_PARTITION` natively. Wire into CI matrix.

4. **Switch precommit to pre-commit hooks** (Medium) — Move `mix precommit` checks into `.pre-commit-config.yaml`. Prevents committing broken code.

5. **Add .tool-versions** (Low) — Single source of truth for Elixir/OTP versions. Used by CI, Dockerfile, and developers. Reference: Livebook's `versions` file.

---

## 4. Testing

### Community Standard

| Aspect | Plausible | Firezone | Logflare | Livebook |
|--------|-----------|----------|----------|----------|
| **Test count** | Many (6 partitions × 2 envs) | 319 test files | Large suite | ~92 test files |
| **async: true** | Inconsistent | Majority (only 2 files sync) | Yes | 54/54 modules async |
| **Factories** | ExMachina | Hand-rolled `*Fixtures` modules | Standard | Hand-rolled `Livebook.Factory` |
| **HTTP mocking** | Mox + Req.Test stubs | Req.Test (no Mox) | Bypass | Bypass + Req.Test |
| **Coverage** | ExCoveralls | ExCoveralls + Coveralls | ExCoveralls (80% min) | None |
| **Property-based** | Not used | Not used | Not used | Not used |
| **E2E** | Playwright (full suite) | None (LiveView tests cover it) | Playwright | None |
| **Background jobs** | Oban manual mode | Oban manual mode | Standard | No Oban |
| **Test tags** | `:ee_only`, `:ce_build_only`, `:slow` | None observed | None observed | `:k8s`, `:tmp_dir`, auth tags |

**Consensus:** ExMachina or hand-rolled factories, `async: true` by default, Req.Test for HTTP mocking, coverage tracking.

### Your Codebase

- 16 test files found.
- `DataCase` and `ConnCase` (standard Phoenix templates).
- `async: true` available but usage unknown.
- **No factory** — test data is created inline.
- **No HTTP mocking library** — not in deps, not used.
- **No ExCoveralls** — not in deps.
- **No E2E tests**.
- **No property-based tests**.
- **Small test suite** — likely adequate for current scope.

### Gap Analysis

| Gap | Impact |
|-----|--------|
| No factory system | Test setup is verbose and inconsistent |
| No HTTP mocking library | Can't test external API interactions (NVD API, etc.) |
| No coverage tracking | Can't measure test completeness |
| Small test suite | Core simulation logic may lack edge-case coverage |
| No test tagging | Can't exclude slow/integration tests |

### Recommendations

1. **Add ExMachina or hand-rolled factories** (High) — Test data creation is the #1 friction point as suites grow. Either add `{:ex_machina, "~> 2.8", only: :test}` or create `test/support/fixtures/` modules. Reference: Plausible's `factory.ex` or Firezone's domain-specific `*Fixtures` modules.

2. **Add Req.Test for HTTP mocking** (Medium) — If/when you integrate NVD API or similar external calls, add `Req.Test` stubs. Already have `:req` available. Reference: Firezone's `test/support/mocks/`.

3. **Add ExCoveralls** (High) — Track coverage, set minimum threshold for CI.

4. **Create integration test for core simulation** (High) — The simulation engine (`Simulator`, `Experiment`, `Optimizer`) is the most critical and complex code. Ensure Monte Carlo runs, defense strategy application, and blast-radius computation have dedicated test coverage.

5. **Add test tagging** (Low) — Use `@tag :simulation` for slow simulation tests, `@tag :nvd` for tests hitting external APIs. Configure exclusions in `test_helper.exs`.

---

## 5. Code Organization

### Community Standard

| Aspect | Plausible | Firezone | Logflare | Livebook |
|--------|-----------|----------|----------|----------|
| **Context pattern** | Schema + context (plural names) | Flat schemas + `Database` submodules | Thin context + cache wrapping | No contexts, organized by concept |
| **Background jobs** | Oban (22 workers, cron) | Oban (20 workers, unique jobs, chained) | Oban (alerts, billing) | None (embedded runtime) |
| **Feature flags** | `fun_with_flags` + billing gating | Two-level (global ∧ per-account, compile-time generated) | ConfigCat (Cachex-backed) | Compile-time keyword list |
| **Caching** | ETS + warmer processes + cache behaviour | ETS caches for gateways/clients | ContextCache (read-through) + WAL-based busting | ETS + file persistence (Storage) |
| **DI approach** | Application config | Custom `defconfig` DSL + process-dictionary overrides | Compile-time config + function args | Application config + `:persistent_term` |
| **Protocols/Poly** | `Billing.Feature` behaviour | `Cache.Cacheable` protocol | 14 adaptor behaviours | `Runtime` + `FileSystem` protocols |

**Consensus:** Context modules as service layer, Oban for async work, feature flags for gating, config-driven DI.

### Your Codebase

- **Context pattern** used — `NetworkDefense.Graph`, `NetworkDefense.Simulation`, `NetworkDefense.Optimization`, etc.
- Clean separation: `lib/network_defense/` (domain) and `lib/network_defense_web/` (web).
- Contract types defined in `contracts/` directories (shared with frontend).
- **No Oban** — no background job system.
- **No feature flags**.
- **No caching abstraction**.
- **No custom protocols/behaviours** for polymorphism.
- **No GenServer usage** in domain logic — all simulation is synchronous in-process.
- **No clustering** (uses `DNSCluster` for basic service discovery, not BEAM clustering).

### Gap Analysis

| Gap | Impact |
|-----|--------|
| No Oban | Long-running simulations block the web process. No retry, no scheduling, no monitoring |
| No feature flags | Can't gradually roll out new simulation strategies or defense types |
| No caching abstraction | Repeated expensive queries (graph traversals, NVD lookups) hit DB every time |
| No behaviours for simulation strategies | Strategy pattern (Greedy, Mincut, Random) uses ad-hoc interfaces — hard to add new ones consistently |
| Sync-only simulation | Web process blocks during Monte Carlo runs. Affects UX. |

### Recommendations

1. **Move simulation runs to Oban** (Critical) — Monte Carlo simulation is CPU-intensive and blocking the web process. Move `Simulation.Run` to an Oban worker with `queue: :simulation`, `max_attempts: 1`. Results saved to DB, frontend polls/pushes for completion. You already have Phoenix PubSub — use it for completion notifications.

2. **Define a Strategy behaviour** (Medium) — The optimization strategies (`GreedyStructuralStrategy`, `RandomStrategy`, `MincutStrategy`, `NullStrategy`) have ad-hoc interfaces. Define a `NetworkDefense.Optimization.Strategy` behaviour with `@callback optimize(budget, graph, opts) :: {:ok, actions} | {:error, reason}`. Then implement each strategy. Reference: Logflare's `Adaptor` behaviour or Livebook's `Runtime` protocol.

3. **Cache expensive graph queries** (Medium) — Add ETS caching for computed graph metrics (reachability, min cuts, etc.) that are queried repeatedly during simulation. Use `ConCache` or hand-rolled ETS.

4. **Add feature flag system** (Low) — When you need to compare simulation strategies or gate new defense types, add a simple compile-time feature flag list (ref: Livebook's compile-time flags) or `fun_with_flags` (ref: Plausible).

5. **Refactor contract types into shared library** (Low) — Currently contracts are duplicated/inline. Extract shared types that both frontend and backend import.

---

## 6. Summary

### Quick Table

| Aspect | Your Codebase | Community Standard | Gap Level |
|--------|--------------|-------------------|-----------|
| **Error tracking** | None | Sentry everywhere | ❌ Missing |
| **Health check** | None | All 4 have `/health` or `/readyz` | ❌ Missing |
| **CI/CD** | None | 2-14 workflows per project | ❌ Missing |
| **Coverage** | None | ExCoveralls (3/4) | ❌ Missing |
| **Background jobs** | None | Oban in 3/4 projects | ❌ Missing |
| **Business metrics** | None (empty periodic_measurements) | Custom metrics in 3/4 | ❌ Missing |
| **Test factories** | Inline | ExMachina or hand-rolled fixtures | ⚠️ Weak |
| **HTTP mocking** | None | Req.Test / Bypass / Mox | ⚠️ Weak |
| **BEAM process metrics** | None (basic VM only) | 3/4 have process-level metrics | ⚠️ Weak |
| **Feature flags** | None | Present in 3/4 | ⚠️ Weak |
| **Caching** | None | Present in 3/4 | ⚠️ Weak |
| **Error handling** | Basic Phoenix defaults | Custom fallback controllers | ⚠️ Basic |
| **OpenTelemetry** | Bandit + Phoenix + Ecto | Same + Oban + Logger metadata | ✅ Good |
| **Structured logging** | Custom LoggerJSON formatter | logger_json or ex_json_logger | ✅ Good |
| **Docker** | Multi-stage with tini | Multi-stage (all) | ✅ Good |
| **Logging infra** | Full Grafana stack in docker/ | Comparable | ✅ Good |
| **Code separation** | Domain vs Web | Domain vs Web (all) | ✅ Good |
| **Async tests** | Available (via `async: true`) | Dominant pattern | ✅ Good |

### Priority-Ranked Recommendations

| # | Recommendation | Priority | Category | Effort |
|---|---------------|----------|----------|--------|
| 1 | **Add GitHub Actions CI** | Critical | Infra/CI | 1 day |
| 2 | **Move simulations to Oban** | Critical | Code Org | 2-3 days |
| 3 | **Add Sentry error tracking** | Critical | Observability | 0.5 day |
| 4 | **Add health check endpoint** | Critical | Observability | 0.5 day |
| 5 | **Add ExCoveralls + coverage threshold** | High | Testing | 0.5 day |
| 6 | **Add simulation business metrics** | High | Observability | 1 day |
| 7 | **Add test factories (ExMachina or custom)** | High | Testing | 1 day |
| 8 | **Add FallbackController** | High | Error Handling | 0.5 day |
| 9 | **Add test for core simulation engine** | High | Testing | 1-2 days |
| 10 | **Add trace-log correlation (trace_id in Logger)** | Medium | Observability | 0.5 day |
| 11 | **Add Req.Test for HTTP mocking** | Medium | Testing | 0.5 day |
| 12 | **Define Strategy behaviour for optimization** | Medium | Code Org | 1 day |
| 13 | **Add test partitioning in CI** | Medium | Infra/CI | 0.5 day |
| 14 | **Cache expensive graph queries (ETS)** | Medium | Code Org | 1 day |
| 15 | **Add .tool-versions** | Low | Infra/CI | 0.25 day |
| 16 | **Move precommit to pre-commit hooks** | Low | Infra/CI | 0.5 day |
| 17 | **Add feature flag system** | Low | Code Org | 1 day |
| 18 | **Enable LiveDashboard in prod** | Low | Observability | 0.25 day |
