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
 - `promtail` - fetching and converting Elixir logs to Loki log format. This is workaround due to sending logs to OTel is in experimental phase in Elixir/Erlang

See `docker-compose.*.yml` files

## Dev environment

`up.sh` script for convenience

- `up.sh dev` - full stack
- `up.sh logs` - tails docker logs from all containers
` -up.sh logs -f <container name>` - logs from selected container

Environment variables & secrets (temp) stored in `.env` file

## Production environment

Not set up yet.