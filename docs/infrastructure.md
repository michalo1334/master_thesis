# Infrastructure

Provisioning managed by Terraform, utilizing Docker. Modules and environments stored in `infra/` directory.

## Secrets and configuration

Non-sensitive configuration values are passed via environment variables (`TF_VAR_*`),

Secrets are volume mounted, one secret per file.

This method provides unified, provider-agnostic way of passing configuration values and secrets to the application.

## Local

`environments/local` is local development stack: fully containerized, application using `hot reloadable` source code with IEx shell attached and observability using Grafana, Loki, Tempo, Prometheus.
Database is also inside container along with PGAdmin.

`environments/local/terraform.sh` is a helper script that forwards TF subcommands with environment variables preloaded from `.env` file.
Dockerized `hashicorp/terraform:1.15.8` only.

Layout:

```text
infra/environments/local/{backend.tf, versions.tf, variables.tf, locals.tf, main.tf, outputs.tf, terraform.sh}
infra/modules/local/{app,database,observability}/{versions.tf, variables.tf, locals.tf, main.tf, outputs.tf}
```

Variables and outputs are alpha-ordered; `locals.tf` holds derived values; `backend.tf` is explicit `local`; child `versions.tf` declares `kreuzwerker/docker` (pin in root).
See `docs/azure-dev-plan.md` for deferred Azure production layout.

### App replicas and clustering

`TF_VAR_app_replicas` (default `2`, `1..5`) in `infra/environments/local/.env` controls `docker_container.app` `count` in `infra/modules/local/app/main.tf`.
Replicas share DNS alias `app` on `network-defense-local-network`; each also has `app-N`. Primary `app-0` alone publishes host ports `4000,4001,5173,9229` to avoid `127.0.0.1` collision.

Distribution: `infra/modules/local/app/locals.tf` `cluster_env` sets per replica `DNS_CLUSTER_QUERY=app`, `LOG_FILE_PATH=app-N.jsonl`, `OTEL_RESOURCE_ATTRIBUTES=replica=app-N`, and `RELEASE_NODE=app-N@app-N`.
`dns_cluster` (`src/mix.exs`, `src/config/runtime.exs` `dns_cluster_query` top-level, `src/lib/network_defense/application.ex` `DNSCluster`) forms longnames `app@IP` (see `src/Dockerfile.dev` `elixir --name app@$(hostname -i)` and `src/rel/overlays/bin/server` `erlang-cookie` file secret).
Single-node still works: `TF_VAR_app_replicas=1` keeps `Node.list()==[]` when `:ignore`.

Observability: `infra/modules/local/observability/config/prometheus.yaml` scrapes `app-0:4001`/`app-1:4001`; `infra/modules/local/observability/config/alloy-config.alloy` extracts `replica` from `filename` (`app-N.jsonl`) on shared `network-defense-local-logs` volume.
Logs per replica avoid interleave; metrics/traces carry `replica`/`service.instance.id`.

Modules used:
 - `app` - application container, `count` via `app_replicas`, dev/prod mode; `erlang-cookie` secret in `infra/environments/local/secrets/` (`0600`)
 - `database` - database, includes containerized Postgres and PGAdmin
 - `observability` - observability stack

## Production

Deferred. `docs/azure-dev-plan.md` retains full design (bootstrap + AVM from `environments/dev`, no `modules/azure` wrappers).
Constraints to preserve: `TF_VAR_*` + file-per-secret (`*_FILE` to `/run/secrets`, also via Key Vault `volumeMounts` in prod), `REPO_*` DB contract, and strict provider separation — Docker Postgres/PgAdmin and self-hosted observability share no abstraction with managed PG + Azure Monitor (LA/AI/DCE/DCR) beyond `*_FILE` until second `azurerm` env exists (YAGNI).

`environments/dev|prod` will use release application images and Azure observability services - Monitor and Application Insights.

Currently WIP.

## Logging setup

Elixir's logger configuration enables writing structured JSONL to `/var/log/network_defense` directory, which is then tailed by Grafana Alloy. Using intermediate file instead of stdin reading separates additional, non-structured logging from compile messages, IEx prompts, banners etc.

Native OTel log export for Erlang/Elixir is currently experimental hence use of file log and Grafana Alloy.

## Health/ready checks

Exposed via `/healthz`, `/readyz` endpoints