defmodule NetworkDefenseWeb.Telemetry do
  use Supervisor

  import Telemetry.Metrics

  @duration_buckets [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60]

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    :erlang.system_flag(:scheduler_wall_time, true)
    :ets.new(:beam_state, [:named_table, :public, :set])

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
      last_value("vm.total_run_queue_lengths.io"),
      last_value("vm_system_counts_process_count",
        event_name: [:vm, :system_counts],
        measurement: :process_count
      ),
      last_value("beam_scheduler_utilization_ratio",
        event_name: [:beam, :scheduler, :utilization],
        measurement: :ratio,
        tags: [:scheduler]
      ),
      sum("beam_gc_collections_total",
        event_name: [:beam, :gc, :collections],
        measurement: :count,
        reporter_options: [prometheus_type: :counter]
      ),
      sum("beam_gc_words_reclaimed_total",
        event_name: [:beam, :gc, :words_reclaimed],
        measurement: :words,
        reporter_options: [prometheus_type: :counter]
      ),
      sum("beam_reductions_total",
        event_name: [:beam, :reductions],
        measurement: :count,
        reporter_options: [prometheus_type: :counter]
      ),
      sum("beam_context_switches_total",
        event_name: [:beam, :context_switches],
        measurement: :count,
        reporter_options: [prometheus_type: :counter]
      ),
      last_value("beam_cluster_nodes",
        event_name: [:beam, :cluster_nodes],
        measurement: :count
      ),
      last_value("oban_queue_depth",
        event_name: [:oban, :queue_depth],
        measurement: :count,
        tags: [:queue, :state, :scope]
      )
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :emit_cpu, []},
      {__MODULE__, :emit_beam, []},
      {__MODULE__, :emit_oban, []}
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

  @oban_states ~w(available scheduled retryable executing)

  @doc false
  def emit_beam do
    emit_scheduler_utilization()
    emit_beam_counters()
    :telemetry.execute([:beam, :cluster_nodes], %{count: 1 + length(Node.list())}, %{})
    :ok
  end

  defp emit_scheduler_utilization do
    case :erlang.statistics(:scheduler_wall_time) do
      schedulers when is_list(schedulers) ->
        online = :erlang.system_info(:schedulers_online)

        for {id, active, total} <- schedulers, id <= online do
          emit_scheduler_sample(id, active, total)
        end

        :ok

      _ ->
        :ok
    end
  end

  defp emit_scheduler_sample(id, active, total) do
    case :ets.lookup(:beam_state, {:scheduler, id}) do
      [] ->
        :ets.insert(:beam_state, {{:scheduler, id}, {active, total}})

      [{_, {prev_active, prev_total}}] ->
        :ets.insert(:beam_state, {{:scheduler, id}, {active, total}})
        emit_scheduler_ratio(id, active - prev_active, total - prev_total)
    end
  end

  defp emit_scheduler_ratio(id, active_delta, total_delta)
       when total_delta > 0 and active_delta >= 0 do
    :telemetry.execute(
      [:beam, :scheduler, :utilization],
      %{ratio: active_delta / total_delta},
      %{scheduler: id}
    )
  end

  defp emit_scheduler_ratio(_id, _active_delta, _total_delta), do: :ok

  defp emit_beam_counters do
    {collections, words_reclaimed, _} = :erlang.statistics(:garbage_collection)
    {reductions, _} = :erlang.statistics(:reductions)
    {context_switches, _} = :erlang.statistics(:context_switches)

    emit_delta(:gc_collections, [:beam, :gc, :collections], :count, collections)
    emit_delta(:gc_words_reclaimed, [:beam, :gc, :words_reclaimed], :words, words_reclaimed)
    emit_delta(:reductions, [:beam, :reductions], :count, reductions)
    emit_delta(:context_switches, [:beam, :context_switches], :count, context_switches)

    :ok
  end

  defp emit_delta(key, event_name, measurement, cumulative) when is_number(cumulative) do
    previous =
      case :ets.lookup(:beam_state, key) do
        [{_, value}] -> value
        [] -> 0
      end

    :ets.insert(:beam_state, {key, cumulative})
    delta = cumulative - previous

    if delta >= 0 do
      :telemetry.execute(event_name, %{measurement => delta}, %{})
    else
      :telemetry.execute(event_name, %{measurement => cumulative}, %{})
    end
  end

  @doc false
  def emit_oban do
    if System.get_env("ROLE") == "coordinator" and repo_available?() do
      try do
        emit_oban_depth()
        :ok
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    else
      :ok
    end
  end

  defp repo_available? do
    case Process.whereis(NetworkDefense.Repo) do
      pid when is_pid(pid) -> true
      _ -> false
    end
  end

  defp emit_oban_depth do
    import Ecto.Query

    rows =
      from(j in Oban.Job,
        where: j.state in ^@oban_states,
        group_by: [j.queue, j.state],
        select: {j.queue, j.state, count(j.id)}
      )
      |> NetworkDefense.Repo.all()

    counts = Map.new(rows, fn {queue, state, count} -> {{queue, state}, count} end)
    queues = Application.get_env(:network_defense, :oban_queue_names, [])

    for queue <- queues, state <- @oban_states do
      :telemetry.execute(
        [:oban, :queue_depth],
        %{count: Map.get(counts, {to_string(queue), state}, 0)},
        %{queue: to_string(queue), state: state, scope: "global"}
      )
    end

    :ok
  end
end
