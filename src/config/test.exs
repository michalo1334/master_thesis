import Config
config :network_defense, Oban, testing: :manual

config :network_defense, NetworkDefense.Compute.ScatterGather,
  executor: NetworkDefense.Compute.LocalExecutor

config :network_defense, :rabbitmq,
  host: "localhost",
  port: 5672,
  virtual_host: "/",
  username: "guest",
  password: nil,
  max_message_bytes: 1_048_576,
  result_inactivity_timeout_ms: 30_000

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
repo_password =
  case System.get_env("REPO_PASSWORD_FILE") || System.get_env("POSTGRES_PASSWORD_FILE") do
    path when is_binary(path) -> path |> File.read!() |> String.trim()
    nil -> System.get_env("REPO_PASSWORD") || System.get_env("POSTGRES_PASSWORD") || "postgres"
  end

database_config = [
  username: System.get_env("REPO_USERNAME") || System.get_env("POSTGRES_USER") || "postgres",
  password: repo_password,
  hostname: System.get_env("REPO_HOSTNAME") || "localhost",
  port: System.get_env("REPO_PORT", "5432") |> String.to_integer(),
  database: "network_defense_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
]

config :network_defense, NetworkDefense.Repo, database_config

config :gust,
       Gust.Repo,
       database_config
       |> Keyword.put(:migration_source, "gust_schema_migrations")
       |> Keyword.put(:pool_size, 5)

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :network_defense, NetworkDefenseWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: System.get_env("SECRET_KEY_BASE") || String.duplicate("a", 64),
  server: false

config :network_defense, :metrics_port, 0

# Test-only Pilot limits. The application and Stage 2 and Stage 3 paths start
# without them. Manual checks supply their own explicit values.
config :network_defense, NetworkDefense.Evaluation.Pilot.Limits,
  snapshot_payload_bytes: 2_097_152,
  snapshot_comparisons: 16,
  comparison_count: 16,
  candidate_count: 16,
  plans_per_side: 256,
  attack_columns: 512,
  work_items: 1024,
  outer_subsamples: 128,
  bootstrap_replicates: 1024,
  candidate_request_bytes: 1_048_576

# Synthetic test-only Final resource limits. They guard the comparison endpoint
# used by Final, which the Pilot caps do not cover. They are not scientific
# settings and not deployment values: Stage 5 real-study caps stay unapproved.
config :network_defense, NetworkDefense.Evaluation.Final.Limits,
  max_bootstrap_replicates: 1_000,
  max_total_work: 1_000_000

config :network_defense, NetworkDefense.Evaluation.Study.CollectionLimits,
  max_phase_items: 24,
  max_gust_concurrency: 2

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
