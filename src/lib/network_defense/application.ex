defmodule NetworkDefense.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:network_defense, :repo])
    OpentelemetryOban.setup(job: [span_relationship: :link])
    NetworkDefense.Observability.attach()

    # Registers the :file_log handler from `config :network_defense, :logger`
    # (set in runtime.exs). Returns {:error, _} if the path is not writable;
    # we keep the app booting and surface the failure so operators notice.
    case Logger.add_handlers(:network_defense) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("file log handler not installed: #{inspect(reason)}")
    end

    node_js_children =
      if Application.get_env(:live_svelte, :ssr_module, nil) == LiveSvelte.SSR.NodeJS do
        [{NodeJS.Supervisor, [path: LiveSvelte.SSR.NodeJS.server_path(), pool_size: 4]}]
      else
        []
      end

    children =
      node_js_children ++
        [
          {Task.Supervisor, name: NetworkDefense.TaskSupervisor},
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
          {Oban, Application.fetch_env!(:network_defense, Oban)},
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
