import Config

alias NetworkDefense.RuntimeConfig

if config_env() == :dev do
  RuntimeConfig.load_dotenv()
end

config :network_defense, :analysis_service,
  url: System.get_env("ANALYSIS_SERVICE_URL"),
  connect_timeout_ms:
    System.get_env(
      "ANALYSIS_SERVICE_CONNECT_TIMEOUT_MS",
      to_string(Application.get_env(:network_defense, :analysis_service)[:connect_timeout_ms])
    )
    |> String.to_integer(),
  timeout_ms:
    System.get_env(
      "ANALYSIS_SERVICE_TIMEOUT_MS",
      to_string(Application.get_env(:network_defense, :analysis_service)[:timeout_ms])
    )
    |> String.to_integer(),
  max_zip_bytes:
    System.get_env(
      "ANALYSIS_SERVICE_MAX_ZIP_BYTES",
      to_string(Application.get_env(:network_defense, :analysis_service)[:max_zip_bytes])
    )
    |> String.to_integer()

pubsub_opts =
  case System.get_env("PUBSUB_ADAPTER") do
    "redis" ->
      [
        adapter: Phoenix.PubSub.Redis,
        redis_opts: [
          host: System.get_env("REDIS_HOST", "redis"),
          port: System.get_env("REDIS_PORT", "6379") |> String.to_integer(),
          password: RuntimeConfig.read_secret("REDIS_PASSWORD")
        ],
        node_name: System.get_env("PUBSUB_NODE_NAME") || node()
      ]

    "pg2" ->
      []

    nil ->
      []

    other ->
      raise "Unknown PUBSUB_ADAPTER #{inspect(other)}. Use redis or pg2."
  end

config :network_defense, :pubsub, pubsub_opts

if (config_env() == :prod or System.get_env("REPO_HOSTNAME")) ||
     RuntimeConfig.read_secret("DATABASE_URL") do
  repo_config =
    if System.get_env("REPO_HOSTNAME") do
      [
        username:
          System.get_env("REPO_USERNAME") || System.get_env("POSTGRES_USER") ||
            raise("expected REPO_USERNAME or POSTGRES_USER environment variable"),
        password:
          RuntimeConfig.read_secret("REPO_PASSWORD") ||
            RuntimeConfig.read_secret("POSTGRES_PASSWORD") ||
            raise("expected REPO_PASSWORD or POSTGRES_PASSWORD environment variable"),
        hostname: System.fetch_env!("REPO_HOSTNAME"),
        port: System.fetch_env!("REPO_PORT") |> String.to_integer(),
        database:
          System.get_env("REPO_DATABASE") || System.get_env("POSTGRES_DB") ||
            raise("expected REPO_DATABASE or POSTGRES_DB environment variable")
      ]
    else
      [
        url:
          RuntimeConfig.read_secret("DATABASE_URL") ||
            raise("expected REPO_HOSTNAME or DATABASE_URL environment variable")
      ]
    end

  config :network_defense, NetworkDefense.Repo, repo_config

  if config_env() == :dev do
    config :network_defense, NetworkDefense.Repo,
      stacktrace: true,
      show_sensitive_data_on_connection_error: true

    config :network_defense, NetworkDefenseWeb.Endpoint,
      http: [
        ip:
          System.get_env("PHX_IP", "127.0.0.1")
          |> String.split(".")
          |> Enum.map(&String.to_integer/1)
          |> List.to_tuple(),
        port: String.to_integer(System.get_env("PORT") || "4000")
      ],
      secret_key_base: RuntimeConfig.read_secret("SECRET_KEY_BASE"),
      live_view: [
        signing_salt: RuntimeConfig.read_secret("LIVE_VIEW_SIGNING_SALT", "dev-only-signing-salt")
      ]
  end
end

config :opentelemetry,
  resource: %{
    service: %{
      name: System.get_env("OTEL_SERVICE_NAME", "network_defense"),
      version: System.get_env("OTEL_SERVICE_VERSION", "unknown")
    }
  }

case System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
  endpoint when is_binary(endpoint) and endpoint != "" ->
    config :opentelemetry, traces_exporter: :otlp

    config :opentelemetry_exporter,
      otlp_protocol: :http_protobuf,
      otlp_endpoint: endpoint

  _ ->
    config :opentelemetry, traces_exporter: :none
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/network_defense start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :network_defense, NetworkDefenseWeb.Endpoint, server: true
end

# File logger: structured JSON emitted to a file consumed by Grafana Alloy.
# Stdout (via :default_handler in config.exs) stays active for dev console.
# Only the file stream is scraped by Alloy, excluding non-Logger stdio noise
# (compile, IEx, banners).
#
# Active in releases (prod) and when LOG_FILE_PATH is explicitly set (dev in
# docker). Local `mix phx.server` without docker skips it so it never tries to
# create /var/log/network_defense on the host. Override path and level via
# LOG_FILE_PATH / LOG_FILE_LEVEL.
enable_file_log =
  config_env() == :prod or System.get_env("LOG_FILE_PATH") != nil

if enable_file_log do
  log_file = System.get_env("LOG_FILE_PATH", "/var/log/network_defense/network_defense.jsonl")
  File.mkdir_p!(Path.dirname(log_file))

  level =
    case System.get_env("LOG_FILE_LEVEL", "info") do
      "debug" -> :debug
      "info" -> :info
      "warning" -> :warning
      "error" -> :error
      _ -> :info
    end

  config :network_defense, :logger, [
    {:handler, :file_log, :logger_std_h,
     %{
       level: level,
       formatter: {NetworkDefense.Observability.LoggerFormatter, metadata: :all},
       config: %{
         file: ~c"#{log_file}",
         filesync_repeat_interval: 5000,
         file_check: 5000,
         max_no_bytes: 100_000_000,
         max_no_files: 5,
         compress_on_rotate: true
       }
     }}
  ]
end

config :network_defense, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

if config_env() == :prod do
  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  ssl_enabled = System.get_env("DB_SSL") in ~w(true 1)

  config :network_defense, NetworkDefense.Repo,
    ssl: ssl_enabled,
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  secret_key_base =
    RuntimeConfig.read_secret("SECRET_KEY_BASE") ||
      raise "expected SECRET_KEY_BASE or SECRET_KEY_BASE_FILE environment variable"

  live_view_signing_salt =
    RuntimeConfig.read_secret("LIVE_VIEW_SIGNING_SALT") ||
      raise "expected LIVE_VIEW_SIGNING_SALT or LIVE_VIEW_SIGNING_SALT_FILE environment variable"

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :network_defense, NetworkDefenseWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    live_view: [signing_salt: live_view_signing_salt],
    cache_static_manifest_latest: PhoenixVite.cache_static_manifest_latest(:network_defense)

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :network_defense, NetworkDefenseWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :network_defense, NetworkDefenseWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
