# Infrastructure

Terraform provisions the local Docker simulator. The modules and environments
live in `infra/`.

The simulator exercises isolated BEAM sites, shared services, active-active
browser routing, and central observability. It does not emulate cloud control
planes, IAM, quotas, WAN behavior, or provider failures.

## Prerequisites

Local provisioning needs a working Docker engine and Docker CLI. The helper
runs Terraform in a container. The secret bootstrap helper also needs Python 3.
The exercised platform is Linux. Local provisioning checks do not establish
production readiness.

## Configuration

Refer to `infra/environments/local/` for the source of truth.

The helper uses one fixed checked-in common manifest. It defines the deployment
network, application, PubSub, and database objects. The checked-in local auto
tfvars file defines local component objects for host access and the secret
directory. The helper passes the common manifest to Terraform commands that
evaluate configuration; Terraform loads the local auto tfvars file normally.

After `./terraform.sh init`, run `./init-secrets.py` from the local environment
directory. It asks Terraform for the configured directory and required paths,
then creates missing random secrets with owner-only permissions. It preserves
existing values and rejects unsafe paths or permissive existing files.

Secrets are mounted read-only. The environment also checks that the required
files exist before apply (see `main.tf` and `locals.tf`). Keep normal read
permissions on the source checkout; restrict the secret directory, not the
whole repository.

Redis and RabbitMQ require their password files with mode `0600`. The bootstrap
helper can create them, or an operator can provision them. Terraform mounts the
paths and never reads their values.

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
  app/            Phoenix application
  database/       Postgres and pgAdmin
  haproxy/        Local browser edge
  observability/  Central Grafana, Prometheus, logs, traces, and exporters
  rabbitmq/       Shared cross-site compute broker
  redis/          Authenticated ephemeral Phoenix PubSub broker
```

`environments/local/terraform.sh` is the local helper. It runs Dockerized
Terraform with the fixed deployment manifest.

## Local lifecycle

Run Terraform through the helper script:

- `terraform.sh init` prepares the providers and modules.
- `init-secrets.py` creates missing local secrets without rotating existing ones.
- `terraform.sh plan` previews changes. Review it before applying.
- `terraform.sh apply` creates or updates the stack.
- `terraform.sh output` prints the exported values, including the published
  service URLs and per-site primary node names (see `outputs.tf` in the
  environment root).
- `terraform.sh destroy` removes the stack.

Refer to the environment files for the accepted variables and exported
outputs rather than fixed URLs or ports.

The `urls` output contains five service URLs: application, PostgreSQL, Grafana,
pgAdmin, and Prometheus. The application URL reaches HAProxy over local HTTP.
Application nodes do not publish browser, Vite, or metrics ports. Only the
primary site's API node retains the debugger publication. Use `urls` as the
source of truth for published service URLs.

## Observability services

The observability module runs Grafana, Prometheus, Tempo, Loki, Alloy, and
infrastructure exporters on the central observability network. It also runs one
collector per site. Each collector joins its site network and the observability
network. Grafana and Prometheus are the only published observability entry
points.

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

The app exposes health and readiness endpoints. HAProxy checks API readiness
before it routes browser traffic. The readiness check depends on PostgreSQL, not Redis. See the app and HAProxy
module source for the health check paths.

Terraform waits for configured container health checks and for the setup
container to exit successfully. These checks show local readiness only. They do
not prove end-to-end telemetry delivery or cross-site behavior. A site collector validates its rendered configuration; that does not
prove it can scrape every target or export every signal.

## Native Evaluation2 runtime

The native study path runs inside the normal application. It uses PostgreSQL, Gust and the retained optimization/simulation executor.
Nx float64, CPU EXLA and Decimal perform statistics in-process. The kernel uses EXLA's host client.
Legacy deployment-source wiring remains until the separate verification/deletion gate; leave it unchanged during a documentation refresh.

Before setup or tests, verify both `NetworkDefense.Repo` and `Gust.Repo` targets.
They have separate migration histories, even when they share one local PostgreSQL service.
The application migrations precede Gust migrations; seeding follows both.
The existing `mix ecto.setup` alias encodes that order for an authorized fresh environment.
Do not reset an existing development database to run a study.

| Configuration | Native requirement |
|---|---|
| Repo connection | Use the intended local host, port, database and credentials for both Repos. Runtime supports `REPO_*` settings or `DATABASE_URL` |
| Secrets | Keep passwords in the existing file-secret mechanism, such as `REPO_PASSWORD_FILE`; exclude values from YAML, commands and reports |
| `GUST_ROLE` | Execution commands default to `core`; `console` and `web` do not dispatch. Inspection/create/cancel force `console` |
| `EVALUATION_MEASURED_ENVIRONMENT_REVISION` | Set a stable truthful label before revision creation; preserve it through Final boundaries and acceptance |
| ScatterGather executor | Check its configured transport. Real native verification used the retained RabbitMQ executor and consumers |
| Broker connection | Use the existing RabbitMQ host/port/vhost/user and file-secret settings when that executor is selected |
| Measurement lifetime | Keep the owning application VM and clock alive during an incomplete measured tier |

A configured label is an operator assertion, rather than an authenticated runtime fingerprint.
Completed timings survive through stored Gust receipts; a lost incomplete session cannot supply missing durations.
Read-only command startup leaves queued Gust work unclaimed, while normal application dependencies still apply.

The current local development evidence does not authorize Terraform apply, service deletion or a new deployment.
Use the [operator guide](evaluation2.md) for commands and safe sandbox example checks.
The [verification record](history/evaluation2-verification.md) states the observed protocol and retained-tree checks.
The [calibration report](history/evaluation2-calibration-20261031.md) records the completed synthetic protocol and its scientific limits.

## Teardown

`terraform.sh destroy` removes every Terraform-managed resource: containers,
networks, all data and log volumes, and the locally built images.
Host secret files and Terraform state are not managed by Terraform and remain
on disk after destroy.

## RabbitMQ

RabbitMQ carries cross-site work delivery. It attaches to every site network
and the central observability network. Application nodes reach it over AMQP
0-9-1 while Erlang distribution stays site-local.

- Credentials arrive as a file-mounted secret, matching the existing secret
  convention. The password is never a Terraform value.
- Messages are transient. The broker keeps no durable intermediate records and
  mounts no local data volume.
- RabbitMQ enables its Prometheus plugin. Central Prometheus scrapes the broker
  directly over the observability network. It collects queue depth,
  unacknowledged messages, consumer count, delivery rate, acknowledgement rate,
  and redelivery rate.
- Use TLS for broker traffic that leaves a private deployment network.
- The app module reads connection values (host, port, virtual host,
  username) from environment variables, not from an AMQP URL.

Apply the stack. Then run the opt-in broker test from `src/` with the command
in [the executor design](design/rabbitmq-distributed-executor.md#local-broker-exercises).
