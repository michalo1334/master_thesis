# Infrastructure

Docker Compose assembles adapters around the application. The application depends only on a database URL, Phoenix secret, optional OTLP endpoint, and optional log-file path.

| File | Purpose |
| --- | --- |
| `compose.app.yml` | Application contract and readiness check. |
| `compose.postgres.yml` | Local PostgreSQL adapter. |
| `compose.observability.grafana.yml` | Grafana, Loki, Tempo, Prometheus, Alloy, and OTEL Collector adapter. |
| `compose.tools.yml` | Developer-only pgAdmin profile. |
| `compose.dev.yml` | Local credentials, source mounts, and loopback ports. |
| `compose.prod.yml` | Private-demo deployment, file-based secrets, and migration job. |

`./docker/up.sh dev` assembles the complete development stack. `./docker/up.sh infra` starts its dependencies while the app runs on the host. Both commands use `src/.env` for local values.

Production combines the application, PostgreSQL, observability, and production overlays. Start it with `PROD_ENV_FILE=/path/to/deployment.env ./docker/up.sh prod`. The environment file requires `APP_IMAGE`, `PHX_HOST`, `POSTGRES_USER`, `POSTGRES_DB`, `GRAFANA_USER`, and paths in `DATABASE_URL_FILE`, `SECRET_KEY_BASE_FILE`, `LIVE_VIEW_SIGNING_SALT_FILE`, `POSTGRES_PASSWORD_FILE`, and `GRAFANA_PASSWORD_FILE`. Secret files must be readable only by the deployment user.

## Logging pipeline

Elixir's `:logger` writes structured JSON to `/var/log/network_defense/network_defense.jsonl` via an OTP `:logger_std_h` handler registered in `src/lib/network_defense/application.ex`. The file lives on the shared `network-defense-logs` Docker volume, which Grafana Alloy mounts read-only and tails with `loki.source.file` (see `docker/alloy-config.alloy`). The bootloader stdout handler stays on for `docker logs`/dev console, but only the file is scraped by Alloy.

Why a file and not the container stdio: the stdio stream mixes `Logger.*` output with non-Logger noise (compile messages, IEx prompts, framework banners). The file handler receives only Logger events, so Loki never sees the noise.

Native OpenTelemetry log export (push OTLP `LogRecord`s to the collector) is the eventual target. The Erlang/Elixir SDK exposes the logs signal only through the `opentelemetry_experimental` app (still non-GA upstream, latest 0.6.x). This file-based path is the stable interim: when the logs signal is promoted to the stable SDK, switch the handler to `:otel_log_handler` and add a `logs` pipeline to the collector config.

## Development

- `./docker/up.sh dev` starts the complete stack.
- `./docker/up.sh logs [service]` tails logs.
- `./docker/up.sh down` stops the stack.
- `./docker/up.sh down-all` also removes volumes.

## Private Demo Deployment

The migration service runs the release migration command before the app starts. The app exposes `/healthz` for process liveness and `/readyz` for database readiness. App and Grafana ports bind to loopback by default; set the documented bind-address variables only when an external reverse proxy is in place.
