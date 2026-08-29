# Planning context

The user requests a plan only. Modify planning artifacts only. Do not build the change.

Goal: prepare the Terraform-managed local stack to simulate distributed Erlang clusters. Include documentation only when the repository's current documentation structure needs an update.

Repository worktree: `/home/michalo/master_thesis-multisite-plan`

Read `/home/michalo/master_thesis-multisite-plan/README.md` first. Follow repository instructions. Distinguish the generic local stack from AWS LocalStack unless evidence proves otherwise.

Every claim must cite a repository file and line range. Separate facts from recommendations and unknowns. Prefer the smallest change that supports a concrete cluster simulation.

## User topology intent

The local model must represent a heterogeneous cloud deployment. Candidate targets include Azure with separate regions or clusters, Pioneer Cloud, and other providers. The user wants Docker-based local connectivity tests. The observability stack remains shared. Terraform must expose flexible topology options. One proposed design defines reusable region instances and a separate interconnectivity module.

## Grilling decisions so far

- Model separate regional Erlang clusters, not one cross-region BEAM mesh.
- Share PostgreSQL across regions.
- Run one analysis service per region.
- The user expects region-to-region distributed execution for optimization, simulation, and analysis. The precise execution model is not yet defined.

## Later grilling decisions

- Use one Terraform root and state for all local deployment sites.
- Default to two sites with two BEAM nodes each.
- Replicas form a BEAM mesh only within their site. Sites use distinct cookies.
- The primary site's first node is the only coordinator and UI entry point. It does not execute workload jobs.
- The other three nodes are workers. Shared PostgreSQL and Oban coordinate fan-out work.
- Run one analysis service per site and one shared observability stack.
- Validate dev mode only. Defer latency, loss, firewall, and partition simulation.
- Defer distributed analysis. Only the primary UI and coordinator initiates
  analysis; it calls the primary site's `analysis` alias. Non-primary analysis
  containers receive no application traffic this phase. Add no analysis Oban
  job, cross-site proxy, second UI, routing metadata, or result workflow now.
  Routed and distributed analysis moves to the later workload-routing and
  map-reduce phase: choose the execution site, have the worker call its
  site-local `analysis` alias, persist the result in PostgreSQL, and broadcast
  progress through Redis. Health checks remain the only current acceptance for
  every analysis container.
- The coordinator needs cross-site progress events. The user prefers a third-party broker such as RabbitMQ, but has not selected one.
- RabbitMQ federation is rejected. Use one shared Redis server and a supported Phoenix PubSub Redis adapter for cross-site broadcasts. Keep Oban/PostgreSQL as the durable job transport.

## Distributed workload decisions (2026-08-29)

The user selected one global Oban worker pool in this phase. The full contract
and EARS cases live in `erlang-multisite-design-draft.md`.

- The primary site replica 0 stays coordinator-only with its workload queues
  disabled.
- Every other node polls the existing `simulations`, `optimizations`, and
  `evaluations` queue names from shared PostgreSQL. No site-specific queue name
  or routing metadata is added.
- Any worker in any site may claim any available whole job. One job is never
  split across nodes in this phase.
- The default two-sites/two-replicas topology gives one worker in the primary
  site and two workers in the other site. Claim share is per worker, not
  balanced by site. The plan promises no round-robin and no equal site
  allocation.
- Progress uses Redis. Durable jobs and results use PostgreSQL. Analysis stays
  separately deferred and UI-local, as already decided.
- A surviving site may claim a newly available job. The plan claims no
  automatic recovery for jobs already executing; current `max_attempts` and
  domain-row behavior is a separate next decision and risk.
- Deferred to the later workload-routing and map-reduce phase: balanced site
  queues, persisted target-site routing, and primary/failover policy.
- No new implementation files are needed beyond the already planned coordinator
  queue override.
- This phase does not revisit global worker-pool semantics.

## Redis decisions (2026-08-29)

- Redis credential mechanism: one mounted plain password file. The container
  startup wrapper generates the ephemeral config from that file. Terraform
  passes only the wrapper script text or path and the mount path, and never
  calls `file()`; no Redis secret value enters Terraform state, static
  container Config.Env, or argv. The health probe necessarily places the value
  in the transient `redis-cli` process environment, and the wrapper writes it
  to the 0600 config.
- Redis image policy: pin `redis:8.2` (Debian-based).
- The Redis container runs one `redis:8.2` container per apply, attached to
  every site network with alias `redis`, no observability attachment, no host
  port, and `/data` mounted as tmpfs so no persistent volume exists.
- Redis mode requires the `redis-password` file. PG2 mode creates no Redis
  module and requires no Redis file.
- State no Redis exporter now; cAdvisor covers basic container metrics. Add a
  redis-exporter only when Redis-specific counters are required.
- The full Redis contract and EARS cases live in `erlang-multisite-design-draft.md`.

## Erlang distribution decision (2026-08-29)

The user selected plain Erlang distribution on private per-site Docker bridges
for this local dev-only phase.

- Cookie authentication plus site-network isolation is accepted only for this
  local simulator. No cookie value travels over a public or routed path. A
  cookie authenticates; it does not encrypt traffic.
- Publish no EPMD or distribution ports. Distinct per-site cookies and networks
  remain mandatory.
- Host Observer uses the same plain distribution path and therefore has
  full-control access to one selected site at a time.
- Do not add TLS certificates, trust stores, `inet_tls` flags, secret files, or
  Terraform resources now.
- Any real multi-host, routed, VPN, cloud, or cross-site distribution design
  must use TLS distribution with peer verification and must not reuse this
  local exception.
- Residual risk: plain distribution authenticates only; it does not encrypt or
  protect against traffic capture on the site bridge. This is accepted because
  the bridge is private and trusted in the local simulator.
- EARS cases and the full contract live in `erlang-multisite-design-draft.md`.

## Operations decisions (2026-08-29)

- Central Grafana is the only all-site view. LiveDashboard and OTP Observer are
  per-site. Redis PubSub does not extend LiveDashboard node visibility.
- Host OTP Observer uses one hidden process per site cookie. It is a
  full-control distribution credential. Separate processes can inspect sites
  concurrently, but no process connects to both meshes.
- On Linux Docker hosts, Observer reaches Docker bridge IPs directly. Do not
  publish EPMD or distribution ports. Do not set a fixed distribution range.
  Docker Desktop needs a later access method.
- Site cookies use `secrets/erlang-cookies/<site>/.erlang.cookie`. Directories
  use mode `0700`. Files use mode `0600`. Apps mount the exact file read-only.
  Host Observer sets `HOME` to the site directory. It uses no cookie flag or
  cookie environment variable.
- The app and root Terraform outputs expose each site's replica-0 Observer
  target as `app@<container-IP>`, from its sole `network_data` address. They
  expose no cookie value. This does not change the primary-site-only
  coordinator role.
- Preserve `docker exec` access in containers. Do not add Observer scripts,
  images, dependencies, host packages, or acceptance checks. Health checks and
  Terraform `wait` remain the only acceptance mechanism.
- observer_cli 2.0, WombatOAM, and PromEx are future suggestions only.

## Terraform configuration decisions (2026-08-29)

The approved design splits Terraform configuration into a provider-neutral
common manifest and a provider-specific local config. The full contract and
EARS cases live in `erlang-multisite-design-draft.md`.

- Provider-neutral common config is a checked-in fixed manifest at
  `infra/deployments/thesis-lab.tfvars`. Terraform does not auto-load this
  sibling file. `terraform.sh` explicitly supplies its absolute `-var-file`
  path for every variable-consuming command. `local.auto.tfvars` auto-loads.
  No `.env` check, no `--env-file`, no manifest selector, and no
  environment-variable validation or allowlist.
- The common object is vertical-sliced. `network` owns site identity and the
  required fixed label fields `provider`, `region`, and `instance`. These are
  labels only and never drive provider placement. `application` owns the
  primary site and the replica counts; its replica keys must exactly equal the
  network site keys. `pubsub` and `database` carry their object fields.
- The manifest retains the selected default two-site, two-node topology and
  the existing labels.
- A provider-free `infra/modules/common/deployment_config` module owns the
  shared object type, validations, normalized config, site map, and node map.
  It creates no resources. Provider roots pass `var.deployment` and consume
  named outputs: `config`, `sites`, `nodes`, `application`, `pubsub`,
  `database`. No consumer receives a bare module object. This prevents schema
  and validation duplication.
- Child modules receive narrow typed slices from the named outputs, not the
  full deployment object. The root fully wires every approved common and local
  component value to the database, conditional Redis, analysis, app, and
  observability modules.
- The database module emits named outputs `postgres_host`, `postgres_port`, and
  `postgres_image`. No consumer receives a bare database module object. The
  app, setup, and observability containers reach PostgreSQL over the Docker
  networks using the named internal host and port outputs, never
  `var.database.host_port`, which remains the database module's loopback
  publication input only.
- The app and setup containers receive `database_host` and `database_port`
  from `module.database.postgres_host` and `module.database.postgres_port`.
  Their base and setup environments set the database host, port, user, name,
  and password-file path. The setup environment excludes analysis, PubSub,
  OTel, role, and node identity settings.
- Common validations: DNS-label-safe deployment name, site keys, and app
  service name; at least one site; 1-5 replicas per site; at least two replicas
  total; primary site exists; application replica keys exactly equal network
  site keys; required identity and label strings nonempty; database name and
  user nonempty and valid PostgreSQL identifiers; pubsub adapter exactly
  `redis` or `pg2`.
- Provider-specific local config is a checked-in
  `infra/environments/local/local.auto.tfvars`, loaded automatically. It uses
  one top-level object variable per component (`application`, `database`,
  `grafana`, `pgadmin`, `prometheus`, `secrets`) with no defaults. All host
  ports are 1-65535 and pairwise unique; the bind address stays fixed to
  loopback. Only app, PostgreSQL, Grafana, pgAdmin, and Prometheus are host
  entry points. The `application` object exposes all four primary-node host
  ports. Analysis, Redis, Loki, Tempo, Alloy, exporters, cAdvisor,
  node-exporter, and per-site collectors have no host port.
- The root validates the range and pairwise uniqueness of all eight host ports.
  It uses a `check` block for cross-component pairwise uniqueness.
- Provider-specific config cannot override common fields. A different common
  intent requires another deployment manifest. The wrapper loads one fixed
  manifest; add a selector only if a second deployment exists.
- `.env` and `.env.example` are removed from the planned local flow. Terraform
  maps tfvars through variables and locals to app-specific container
  environment variables and secret file mounts. Terraform passes paths, never
  secret contents. Provider-specific wrappers own process settings and
  credentials. No environment-variable validation or allowlist is added.
  Secret values remain files.
- The root computes `abspath(var.secrets.directory)` before preconditions and
  mounts.
- Implementation constants stay module-owned: image pins, internal ports,
  health timings, retention, analysis request and extraction limits,
  concurrency limits, and client timeouts. No tfvars for these.
- The analysis module owns one fixed response-size value and outputs it as
  `max_response_size`. The root maps it to the app input
  `analysis_max_zip_bytes`; the app emits `ANALYSIS_SERVICE_MAX_ZIP_BYTES` and
  the service container emits `NETWORK_DEFENSE_ANALYSIS_MAX_RESPONSE_BYTES`.
  The value is not exposed in tfvars. `ANALYSIS_SERVICE_URL` stays derived
  (`http://analysis:8080`) with no URL output. Request and extraction limits
  remain separate implementation constants.
- The setup container is a one-shot `attach=true`, `must_run=false` container
  with no `wait=true`. A lifecycle postcondition requires `self.exit_code == 0`.
  App nodes depend on it. No `local-exec` or `terraform_data` orchestrates it.
  Its environment is the minimum database configuration (named internal
  database host and port, common database user and name, and the
  password-file path) and excludes analysis, PubSub, OTel, role, and node
  identity settings.
- Changing `deployment.name` causes an accepted clean resource rename and
  rebuild with no state migration.
- Removed or replaced scalar root variables: `app_image`, `app_mode`,
  `app_replicas`, `app_port`, `analysis_port`, `grafana_user`,
  `log_file_level`, `log_file_path`, `otel_endpoint`, `pgadmin_email`,
  `phx_host`, `postgres_database`, `postgres_user`, `secret_mount_path`, and
  the root scalar `pubsub_adapter`. Dev-only design removes app image and mode.
  Analysis and OTel URLs are derived. Log paths are derived per site and
  replica. Component values move to objects.
- Terraform outputs derive from component host ports; URLs are not hardcoded.
  Site collector and central Prometheus configuration are generated from
  normalized sites and nodes with `templatefile`; no fixed two-replica target
  list. Service identity derives from `application.service_name`.
- Child modules have required typed inputs without duplicate defaults or a
  dead `secret_files` input. Required secret filenames remain module and root
  implementation contracts; the Redis password remains conditional.
- pgAdmin mounts the `postgres-password` file read-only. Terraform does not
  call `file()`. A container startup wrapper reads it, escapes colon and
  backslash for pgpass, writes `/var/lib/pgadmin/.pgpass` with mode `0600` and
  pgAdmin ownership, and runs the official entrypoint. The static secret-free
  `servers.json` upload stays. The admin password uses the `_FILE` form. The
  pgAdmin env sets non-secret `PGHOST`, `PGPORT`, `PGDATABASE`, and `PGUSER`
  from module locals and `var.database`, and the wrapper uses those values
  directly with no literal defaults.
- Local wrapper no longer requires or loads `.env`; it loads the fixed common
  manifest through the explicit `-var-file` path. `local.auto.tfvars` loads
  automatically. Exactly five approved host service entry points remain.

## BEAM and Oban safeguard metrics decisions (2026-08-29)

The accepted design adds a small set of BEAM and Oban metrics in
`NetworkDefenseWeb.Telemetry`. The full validated detail lives in
`focused-beam-metrics-validated-design.md`.

- One named public ETS set owned by the existing `NetworkDefenseWeb.Telemetry`
  supervisor. No new module, process, or dependency.
- Process-count gauge from the default `[:vm, :system_counts]` poller.
  Prometheus name `vm_system_counts_process_count`.
- Enable `scheduler_wall_time`. The first scheduler sample stores a baseline;
  later regular-scheduler active and total deltas become the ratio gauge
  `beam_scheduler_utilization_ratio`, tagged `scheduler`. The existing
  `vm.cpu.per_core` stays as OS CPU and is distinct from scheduler utilization.
- The four cumulative counters (GC count, GC words reclaimed, reductions,
  context switches) use `Sum` with `prometheus_type: :counter`. They emit
  non-negative deltas; the first sample emits the cumulative baseline, and a
  reset re-applies the first-sample rule. Names: `beam_gc_collections_total`,
  `beam_gc_words_reclaimed_total`, `beam_reductions_total`,
  `beam_context_switches_total`. Grafana uses `rate`.
- Site-cluster node-count gauge `1 + length(Node.list())`, self included,
  hidden observers excluded. This is the node-count-only distribution
  safeguard; distribution traffic is not measured. Name `beam_cluster_nodes`.
  Grafana uses `min by (site)`.
- Oban queue-depth gauges only on `ROLE=coordinator`. Workers never query.
  `runtime.exs` captures the configured queue names before the coordinator's
  `queues: false` override. The poller emits the full configured `queue x state`
  product, including zeros, for the string states `"available"`, `"scheduled"`,
  `"retryable"`, `"executing"`, with tags `queue`, `state`, and `scope=global`.
  The emit function first checks that `NetworkDefense.Repo` is available,
  handles error tuples, rescues exceptions, catches exits, and returns `:ok`
  with no emission on any failure. `telemetry_poller` removes a measurement
  that raises, so containment is required. Name `oban_queue_depth`. Grafana
  uses `max by (queue, state)`, never `sum`.
- Grafana resource-utilization dashboard gains `site` and `replica` variables,
  updates every app-metric panel from `job="network_defense"` to
  `job="site-apps"`, and adds panels for the new metrics.
- Central Prometheus scrapes the site collectors with `honor_labels: true` so
  the receiver `job="site-apps"` label and the site-qualified replica labels
  survive. The labels come from each site collector receiver `static_configs`,
  not from the OTel resource processor (OTLP data only).
- Acceptance is health-check-only. No unit tests, no smoke scripts, no new
  dependencies. Residual risks: reporter reset and scheduler overhead.
