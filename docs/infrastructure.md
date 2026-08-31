# Infrastructure

Terraform provisions the infrastructure using Docker. The modules and
environments live in `infra/`.

The local simulator exercises isolated BEAM sites, shared services, and central
observability before cloud infrastructure exists. It does not emulate cloud
control planes, IAM, quotas, WAN behavior, or provider failures.

## Prerequisites

Local provisioning needs a working Docker engine. The helper script runs
Terraform inside a Docker container, so a docker CLI is required on the host.

## Configuration

Refer to `infra/environments/local/` for the source of truth.

The helper uses one fixed checked-in common manifest. It defines the deployment
network, application, PubSub, and database objects. The checked-in local auto
tfvars file defines local component objects for host access and the secret
directory. The helper passes the common manifest to Terraform commands that
evaluate configuration; Terraform loads the local auto tfvars file normally.

Secrets use files with restrictive permissions, mounted into containers as
read-only. The local secrets object declares the host directory. The environment
enforces via a precondition that all required secret files exist before apply
(see `main.tf` and `locals.tf`).

Redis mode also requires an operator-created `redis-password` file with mode
`0600`. Terraform mounts its path and never reads its value.

Keep the secret directory and its files restricted to the owner. Each
`erlang-cookies/<site>/` directory must have mode `0700`, and its
`.erlang.cookie` file must have mode `0600`. Terraform mounts the exact cookie
file read-only and never exposes its value.

The app reads secrets from files under `/run/secrets`. See the module source
for how each container mounts and reads them.

## Layout

```text
infra/environments/local/   Terraform root for the local environment
infra/deployments/          Provider-neutral deployment manifests
infra/modules/common/       Provider-free deployment configuration validation
infra/modules/local/
  analysis/       Local Python analysis service
  app/            Phoenix application
  database/       Postgres and pgAdmin
  observability/  Central Grafana, Prometheus, logs, traces, and exporters
  redis/          Authenticated ephemeral Phoenix PubSub broker
```

`environments/local/terraform.sh` is the local helper. It runs Dockerized
Terraform with the fixed deployment manifest.

## Local lifecycle

Run Terraform through the helper script:

- `terraform.sh init` prepares the providers and modules.
- `terraform.sh apply` creates or updates the stack.
- `terraform.sh output` prints the exported values, including the published
  service URLs and per-site primary node names (see `outputs.tf` in the
  environment root).
- `terraform.sh destroy` removes the stack.

Refer to the environment files for the accepted variables and exported
outputs rather than fixed URLs or ports.

The `urls` output contains the five host entry points: application, PostgreSQL,
Grafana, pgAdmin, and Prometheus. Use it as the source of truth for published
service URLs.

## Analysis service

The `analysis` module runs one local Python statistical analysis service per
declared site. The service is internal to its site network. The Phoenix app
reaches it through the `analysis` alias. It has no host port. See
`evaluation/analysis/README.md` for its behavior, HTTP interface, and CLI.

## Observability services

The observability module runs Grafana, Prometheus, Tempo, Loki, Alloy, and
infrastructure exporters on the central observability network. Grafana and
Prometheus are the only published observability entry points. Per-site
collectors and application telemetry are added separately.

Grafana is the all-site view. LiveDashboard and OTP Observer are site-local;
Redis PubSub does not extend LiveDashboard across site meshes.

## OTP Observer

Read `site_primary_node_names` from `terraform.sh output` and select one site.
Start one hidden long-name Observer process for that site:

```bash
HOME=/absolute/path/to/secrets/erlang-cookies/<site> \
  erl -name observer_<site-with-hyphens-replaced-by-underscores>@$(hostname -f) \
  -hidden -run observer
```

Connect it to that site's output target. One process must use one site cookie
and one mesh only. A distribution cookie grants full control of the selected
site; it is not read-only access.

This plain-distribution path is accepted only on private Docker bridges on a
Linux host. It does not encrypt traffic. Do not publish EPMD or distribution
ports. Docker Desktop needs a later access method. Use `docker exec` for
in-container diagnostics when host Observer is unsuitable.

## Logging

The app writes site-qualified structured JSONL logs to a shared volume. Alloy
tails those files and writes them to Loki.

## Health and readiness

The app exposes health and readiness endpoints. See the app module source for
the health check paths.

Terraform waits for configured container health checks and for the setup
container to exit successfully. These checks show local readiness only. They do
not prove end-to-end telemetry delivery, cross-site behavior, or analysis
execution. A site collector validates its rendered configuration; that does not
prove it can scrape every target or export every signal.

## Teardown

`terraform.sh destroy` removes every Terraform-managed resource: containers,
networks, all data and log volumes, and the locally built images.
Host secret files and Terraform state are not managed by Terraform and remain
on disk after destroy.
