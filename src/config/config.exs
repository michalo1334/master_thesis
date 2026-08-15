# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :network_defense, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [workflows: 10],
  repo: NetworkDefense.Repo

config :network_defense, :workflow_templates, %{
  "combined_analysis" => NetworkDefense.Analysis.CombinedAnalysisWorkflow
}

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
live_view_signing_salt =
  if config_env() == :prod do
    nil
  else
    System.get_env("LIVE_VIEW_SIGNING_SALT") || "dev-only-signing-salt"
  end

config :network_defense, NetworkDefenseWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: NetworkDefenseWeb.ErrorHTML, json: NetworkDefenseWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: NetworkDefense.PubSub,
  live_view: [signing_salt: live_view_signing_salt]

# Structured JSON logging stays on stdout for `docker logs` and local consoles.
# The Grafana adapter optionally tails the separate file handler from runtime.exs.
config :logger, handle_sasl_reports: true

config :logger, :default_handler,
  formatter: {NetworkDefense.Observability.LoggerFormatter, metadata: :all}

# Ecto telemetry remains active when the default text query logger is disabled.
config :network_defense, NetworkDefense.Repo, log: false

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# OpenTelemetry defaults. Override in env-specific configs.
config :opentelemetry,
  span_processor: :batch

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
