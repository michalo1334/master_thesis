# Infrastructure

This document describes what tech stack is used for infrastructure provisioning and explains configuration for common enviroments (dev, prod)

# Overview

All IaC lives in `docker/` directory.

Docker file for building Elixir application along with Node.js packages is in `src/` directory.

Docker file for development (`Dockerfile.dev`) builds application in development mode with hot reloaded enabled and polling mode for source changes.

Docker Compose is used for provisioning entire infrastructure, both in dev and production environment.

Input values are passed via environment variables.

Secrets are passed via files, mounted as volume. Currently secrets are also passed as env variables for simplicity (only dev env)

The following components are common to all environments.

 - `postgres` - PostgresSQL 18 for storage
 - `network_defense` - Elixir application along with frontend
 - `otel-collector` - OpenTelemetry collector for fetching & dispatching metrics and traces
 - `loki` - Grafana Loki for structured logs. Stored **locally** as mounted volume
 - `tempo` - Grafana Tempo for trace data. Stored **locally** as mounted volume
 - `prometheus` - Prometheus for metrics data. Stored **locally** as mounted volume
 - `alloy` - tails the Elixir `:logger` file output and ships to Loki

See `docker-compose.*.yml` files

## Logging pipeline

Elixir's `:logger` writes structured JSON to `/var/log/network_defense/network_defense.jsonl` via an OTP `:logger_std_h` handler registered in `src/lib/network_defense/application.ex`. The file lives on the shared `network-defense-logs` Docker volume, which Grafana Alloy mounts read-only and tails with `loki.source.file` (see `docker/alloy-config.alloy`). The bootloader stdout handler stays on for `docker logs`/dev console, but only the file is scraped by Alloy.

Why a file and not the container stdio: the stdio stream mixes `Logger.*` output with non-Logger noise (compile messages, IEx prompts, framework banners). The file handler receives only Logger events, so Loki never sees the noise.

Native OpenTelemetry log export (push OTLP `LogRecord`s to the collector) is the eventual target. The Erlang/Elixir SDK exposes the logs signal only through the `opentelemetry_experimental` app (still non-GA upstream, latest 0.6.x). This file-based path is the stable interim: when the logs signal is promoted to the stable SDK, switch the handler to `:otel_log_handler` and add a `logs` pipeline to the collector config.

## Dev environment

`up.sh` script for convenience

- `up.sh dev` - full stack
- `up.sh logs` - tails docker logs from all containers
` -up.sh logs -f <container name>` - logs from selected container

Environment variables & secrets (temp) stored in `.env` file

## Production environment

Not set up yet.
