# Infrastructure

Terraform provisions the infrastructure using Docker. The modules and
environments live in `infra/`.

## Prerequisites

Local provisioning needs a working Docker engine. The helper script runs
Terraform inside a Docker container, so a docker CLI is required on the host.

## Configuration

Refer to `infra/environments/local/` for the source of truth.

The checked-in common manifest defines deployment intent. The checked-in local
auto tfvars file defines host access and operator identities. The helper passes
the common manifest to Terraform commands that evaluate configuration; Terraform
loads the local auto tfvars file normally.

Secrets use files with restrictive permissions, mounted into containers as
read-only. The local secrets object declares the host directory. The environment
enforces via a precondition that all required secret files exist before apply
(see `main.tf` and `locals.tf`).

Redis mode also requires an operator-created `redis-password` file with mode
`0600`. Terraform mounts its path and never reads its value.

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
  redis/          Authenticated ephemeral Phoenix PubSub broker
```

`environments/local/terraform.sh` is the local helper. It runs Dockerized
Terraform with the fixed deployment manifest.

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

The `analysis` module runs one local Python statistical analysis service per
declared site. The service is internal to its site network. The Phoenix app
reaches it through the `analysis` alias. See `evaluation/analysis/README.md`
for its behavior, HTTP interface, and CLI.

## Observability services

Observability is unavailable in temporary States 02-06. The observability
module is removed; metrics, traces, and log collection are not provisioned in
these states.

## Logging

The app writes structured JSONL logs to a file on a shared volume. In States
02-06 the logs remain stored on that volume but are not collected. Collection
returns when a later state reintroduces the observability stack.

## Health and readiness

The app exposes health and readiness endpoints. See the app module source for
the health check paths.

## Teardown

`terraform.sh destroy` removes every Terraform-managed resource: containers,
networks, all data and log volumes, and the locally built images.
Host secret files and Terraform state are not managed by Terraform and remain
on disk after destroy.
