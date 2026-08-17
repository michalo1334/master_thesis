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

Modules used:
 - `app` - application container, configurable in dev or prod mode. Dev mode contains additional hot reload of source code configuration
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