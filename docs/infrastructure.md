# Infrastructure

Terraform manages the local Docker stack from `infra/environments/local`. Non-secret inputs come from its ignored `.env`; secret files remain in its ignored `secrets/` directory.

## Logging pipeline

Elixir's `:logger` writes structured JSON to `/var/log/network_defense/network_defense.jsonl` via an OTP `:logger_std_h` handler registered in `src/lib/network_defense/application.ex`. The file lives on the shared `network-defense-logs` Docker volume, which Grafana Alloy mounts read-only and tails with `loki.source.file` (see `infra/modules/local/observability/config/alloy-config.alloy`). The bootloader stdout handler stays on for `docker logs`/dev console, but only the file is scraped by Alloy.

Why a file and not the container stdio: the stdio stream mixes `Logger.*` output with non-Logger noise (compile messages, IEx prompts, framework banners). The file handler receives only Logger events, so Loki never sees the noise.

Native OpenTelemetry log export (push OTLP `LogRecord`s to the collector) is the eventual target. The Erlang/Elixir SDK exposes the logs signal only through the `opentelemetry_experimental` app (still non-GA upstream, latest 0.6.x). This file-based path is the stable interim: when the logs signal is promoted to the stable SDK, switch the handler to `:otel_log_handler` and add a `logs` pipeline to the collector config.

## Observability scope

The app interface is shared: OTLP endpoint configuration and structured logs with trace and span fields. The collector destination, file tailing, Grafana stack, storage, Docker mounts, and host metrics are local-only. Production selects its own observability implementation.

## Development

`terraform apply` migrates and seeds the development database before starting the app. The app exposes `/healthz` for process liveness and `/readyz` for database readiness.
