import Config

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

if config_env() == :prod do
  read_secret = fn base_var ->
    file_var = base_var <> "_FILE"

    case System.get_env(file_var) do
      path when is_binary(path) ->
        path |> File.read!() |> String.trim()

      nil ->
        System.get_env(base_var) ||
          raise "expected #{base_var} or #{file_var} environment variable"
    end
  end

  database_url = read_secret.("DATABASE_URL")

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  ssl_enabled = System.get_env("DB_SSL") in ~w(true 1)

  config :network_defense, NetworkDefense.Repo,
    ssl: ssl_enabled,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  secret_key_base = read_secret.("SECRET_KEY_BASE")
  live_view_signing_salt = read_secret.("LIVE_VIEW_SIGNING_SALT")

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :network_defense, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

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
