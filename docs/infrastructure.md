# Infrastructure

Terraform provisions the infrastructure using Docker. The modules and
environments live in `infra/`.

## Prerequisites

Local provisioning needs a working Docker engine. The helper script runs
Terraform inside a Docker container, so a docker CLI is required on the host.

## Configuration

Refer to `infra/environments/local/` for the source of truth.

Non-sensitive inputs use environment variables. Prefix them with `TF_VAR_`.
The helper script loads them from the git-ignored `.env` file before every
Terraform run. `.env.example` is the committed template.

Secrets use files with restrictive permissions, mounted into containers as
read-only. The host secrets directory is declared by `secret_mount_path`. The
environment enforces via a precondition that all required secret files exist
before apply (see `main.tf` and `locals.tf`).

The app reads secrets from files under `/run/secrets`. See the module source
for how each container mounts and reads them.

## Layout

```text
infra/environments/local/   Terraform root for the local environment
infra/modules/local/
  analysis/       Local Python analysis service
  app/            Phoenix application
  database/       Postgres and pgAdmin
  observability/  Observability service stack
```

`environments/local/terraform.sh` is the local helper. It runs the Dockerized
Terraform with environment variables preloaded from `.env`.

## Local lifecycle

Run Terraform through the helper script:

- `terraform.sh init` prepares the providers and modules.
- `terraform.sh apply` creates or updates the stack.
- `terraform.sh output` prints the exported values, including the published
  service URLs (see `outputs.tf` in the environment root).
- `terraform.sh destroy` removes the stack.

Refer to the environment files for the accepted variables and exported
outputs rather than fixed URLs or ports.

## Analysis service

The `analysis` module runs the local Python statistical analysis service. The
service runs as a container on the stack network. The Phoenix app reaches it
by its service name. For behavior, HTTP interface, and CLI, see
`evaluation/analysis/README.md`.

## Observability services

The `observability` module runs the following services:
Alloy, cAdvisor, Grafana, Loki, OpenTelemetry Collector, node-exporter,
postgres-exporter, Prometheus, and Tempo.

Published service URLs come from the environment Terraform output.

## Logging

The app writes structured JSONL logs to a file on a shared volume. Grafana
Alloy tails that file. Only this file stream is collected; it excludes
non-structured stdio output such as compile messages and banners.

## Health and readiness

The app exposes health and readiness endpoints. See the app module source for
the health check paths.

## Teardown

`terraform.sh destroy` removes every Terraform-managed resource: containers,
the stack network, all data and log volumes, and the locally built images.
Host files such as `.env`, the secrets directory, and the Terraform state are
not managed by Terraform and remain on disk after destroy.
