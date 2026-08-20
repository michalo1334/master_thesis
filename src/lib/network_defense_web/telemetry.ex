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
      counter("network_defense.evaluation.runs.total",
        event_name: [:network_defense, :evaluation, :run]
      ),
      distribution("network_defense.evaluation.duration.seconds",
        event_name: [:network_defense, :evaluation, :run],
        measurement: :duration,
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      counter("network_defense.evaluation.exports.total",
        event_name: [:network_defense, :evaluation, :export]
      ),
      distribution("network_defense.evaluation.export.duration.seconds",
        event_name: [:network_defense, :evaluation, :export],
        measurement: :duration,
        unit: {:native, :second},
        reporter_options: [buckets: @duration_buckets]
      ),
      last_value("vm.memory.total.bytes",
        event_name: [:vm, :memory],
        measurement: :total,
        unit: :byte
      ),
      last_value("vm.cpu.utilization.percent",
        event_name: [:vm, :cpu],
        measurement: :utilization
      ),
      last_value("vm.cpu.per_core.percent",
        event_name: [:vm, :cpu, :per_core],
        measurement: :utilization,
        tags: [:core]
      ),
      last_value("vm.memory.processes.bytes",
        event_name: [:vm, :memory],
        measurement: :processes,
        unit: :byte
      ),
      last_value("vm.memory.ets.bytes",
        event_name: [:vm, :memory],
        measurement: :ets,
        unit: :byte
      ),
      last_value("vm.memory.binary.bytes",
        event_name: [:vm, :memory],
        measurement: :binary,
        unit: :byte
      ),
      last_value("vm.memory.system.bytes",
        event_name: [:vm, :memory],
        measurement: :system,
        unit: :byte
      ),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :emit_cpu, []}
    ]
  end

  @doc false
  def emit_cpu do
    case :cpu_sup.util([:per_cpu]) do
      cores when is_list(cores) and cores != [] ->
        for {core_id, busy, _non_busy, _extra} <- cores do
          :telemetry.execute([:vm, :cpu, :per_core], %{utilization: busy}, %{core: core_id})
        end

        avg = Enum.reduce(cores, 0.0, fn {_id, busy, _, _}, acc -> acc + busy end) / length(cores)
        :telemetry.execute([:vm, :cpu], %{utilization: avg}, %{})

      _ ->
        :ok
    end
  end
end
