# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :live_svelte, ssr: true

config :phoenix_vite, PhoenixVite.Npm,
  assets: [args: [], cd: Path.expand("..", __DIR__)],
  vite: [
    args: ~w(exec -- vite),
    cd: Path.expand("../assets", __DIR__),
    env: %{"MIX_BUILD_PATH" => Mix.Project.build_path()}
  ]

config :network_defense,
  ecto_repos: [NetworkDefense.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configures the endpoint
config :network_defense, NetworkDefenseWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: NetworkDefenseWeb.ErrorHTML, json: NetworkDefenseWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: NetworkDefense.PubSub,
  live_view: [signing_salt: System.get_env("LIVE_VIEW_SIGNING_SALT") || "32w8i9Ge"]

# Structured JSON logging via logger_json (emitted to stdout).
# Grafana Alloy tails the container stdout and pushes to Loki.
config :logger, handle_sasl_reports: true

config :logger, :default_handler,
  formatter: {NetworkDefense.Observability.LoggerFormatter, metadata: :all}

# Ecto telemetry remains active when the default text query logger is disabled.
config :network_defense, NetworkDefense.Repo, log: false

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# OpenTelemetry defaults. Override in env-specific configs.
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
