defmodule NetworkDefenseWeb.Telemetry do
  use Supervisor

  import Telemetry.Metrics

  @duration_buckets [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60]

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {TelemetryMetricsPrometheus.Core, metrics: metrics()},
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      distribution("phoenix.endpoint.duration.seconds",
        event_name: [:phoenix, :endpoint, :stop],
        measurement: :duration,
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("phoenix.router_dispatch.duration.seconds",
        event_name: [:phoenix, :router_dispatch, :stop],
        measurement: :duration,
        tags: [:route],
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("phoenix.router_dispatch.exception.duration.seconds",
        event_name: [:phoenix, :router_dispatch, :exception],
        measurement: :duration,
        tags: [:route],
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("phoenix.socket_connected.duration.seconds",
        event_name: [:phoenix, :socket_connected],
        measurement: :duration,
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      sum("phoenix.socket_drain.count"),
      distribution("phoenix.channel_joined.duration.seconds",
        event_name: [:phoenix, :channel_joined],
        measurement: :duration,
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("phoenix.channel_handled_in.duration.seconds",
        event_name: [:phoenix, :channel_handled_in],
        measurement: :duration,
        tags: [:event],
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("network_defense.repo.query.total_time.seconds",
        event_name: [:network_defense, :repo, :query],
        measurement: :total_time,
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("network_defense.repo.query.decode_time.seconds",
        event_name: [:network_defense, :repo, :query],
        measurement: :decode_time,
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("network_defense.repo.query.query_time.seconds",
        event_name: [:network_defense, :repo, :query],
        measurement: :query_time,
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("network_defense.repo.query.queue_time.seconds",
        event_name: [:network_defense, :repo, :query],
        measurement: :queue_time,
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("network_defense.repo.query.idle_time.seconds",
        event_name: [:network_defense, :repo, :query],
        measurement: :idle_time,
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      counter("network_defense.simulator.runs.total",
        event_name: [:network_defense, :simulator, :run]
      ),
      distribution("network_defense.simulator.duration.seconds",
        event_name: [:network_defense, :simulator, :run],
        measurement: :duration,
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      counter("network_defense.optimizer.runs.total",
        event_name: [:network_defense, :optimizer, :run]
      ),
      distribution("network_defense.optimizer.duration.seconds",
        event_name: [:network_defense, :optimizer, :run],
        measurement: :duration,
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      last_value("vm.memory.total.bytes",
        event_name: [:vm, :memory],
        measurement: :total,
        unit: :byte
      ),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    []
  end
end
