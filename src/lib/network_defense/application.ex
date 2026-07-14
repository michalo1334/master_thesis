defmodule NetworkDefense.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:network_defense, :repo])

    node_js_children =
      if Application.get_env(:live_svelte, :ssr_module, nil) == LiveSvelte.SSR.NodeJS do
        [{NodeJS.Supervisor, [path: LiveSvelte.SSR.NodeJS.server_path(), pool_size: 4]}]
      else
        []
      end

    children =
      node_js_children ++
        [
          NetworkDefenseWeb.Telemetry,
          {Bandit,
           scheme: :http,
           port: Application.get_env(:network_defense, :metrics_port, 4001),
           plug: NetworkDefenseWeb.MetricsPlug,
           ip: {0, 0, 0, 0}},
          NetworkDefense.Repo,
          {DNSCluster,
           query: Application.get_env(:network_defense, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: NetworkDefense.PubSub},
          # Start a worker by calling: NetworkDefense.Worker.start_link(arg)
          # {NetworkDefense.Worker, arg},
          # Start to serve requests, typically the last entry
          NetworkDefenseWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NetworkDefense.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NetworkDefenseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
