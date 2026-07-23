defmodule NetworkDefense.Simulations do
  @moduledoc """
  Public context module for working with simulation related aspects
  """
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Graph.Graphs
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulation.Simulator
  alias NetworkDefense.Simulation.Runs
  alias NetworkDefense.Simulation.Contracts.RunSimulationRequest

  import Ecto.Query

  require Logger

  def run(opts \\ []) do
    state = Simulator.run(opts)
    {:ok, saved} = Runs.insert(state)
    saved
  end

  def run_experiment(opts \\ []) do
    {experiment, _runs} = Simulator.run_experiment(opts)
    {:ok, saved} = Experiments.insert(experiment)
    saved
  end

  @simulation_events_topic "simulation_events"

  def simulation_events_topic, do: @simulation_events_topic

  def run_async(%RunSimulationRequest{} = request) do
    with {:ok, graph_id} <- Ecto.UUID.cast(request.graph_id),
         graph when not is_nil(graph) <- Graphs.load(graph_id) do
      run_async(graph, request.correlation_id, request.simulation_params)
    else
      :error -> {:error, "invalid_graph_id"}
      nil -> {:error, "graph_not_found"}
    end
  end

  def run_async(graph, correlation_id, simulation_params) do
    rules = default_rules()

    Task.start(fn ->
      try do
        {elapsed_us, {experiment, runs}} =
          :timer.tc(fn ->
            Simulator.run_experiment(
              graph: graph,
              run_count: simulation_params.monte_carlo_trials,
              iteration_count: simulation_params.iterations_per_run,
              initial_attacker_state: initial_attacker_state(graph),
              lock_version: graph.lock_version,
              rules: rules
            )
          end)

        runtime_ms = div(elapsed_us, 1000)

        experiment = %{
          experiment
          | runtime_ms: runtime_ms,
            lock_version: graph.lock_version,
            run_count: length(runs)
        }

        case Experiments.insert(experiment) do
          {:ok, saved} ->
            Logger.info("experiment persisted: #{saved.id} for graph #{saved.graph_id}")

            broadcast_simulation_completed(saved, correlation_id)

          {:error, reason} ->
            Logger.error("Failed to persist simulation: #{inspect(reason)}")
            broadcast_simulation_failed(graph.id, correlation_id, inspect(reason))
        end
      rescue
        e ->
          Logger.error("Simulation task crashed: #{inspect(e)}")
          broadcast_simulation_failed(graph.id, correlation_id, Exception.message(e))
      catch
        kind, reason ->
          Logger.error("Simulation task exited: #{kind}: #{inspect(reason)}")
          broadcast_simulation_failed(graph.id, correlation_id, "#{kind}: #{inspect(reason)}")
      end
    end)
  end

  def list_experiments(graph_ids) when is_list(graph_ids) do
    query =
      from experiment in Experiment,
        where: experiment.graph_id in ^graph_ids,
        order_by: [desc: :inserted_at],
        preload: [:graph]

    Repo.all(query)
  end

  def list_experiments(graph_ids), do: list_experiments([graph_ids])

  defp initial_attacker_state(graph) do
    internet_host =
      graph
      |> NetworkDefense.Graph.Graph.nodes()
      |> Enum.find(fn node ->
        short_type = node.type |> Module.split() |> List.last()
        short_type == "Host" and Map.get(node.data, "name") == "internet"
      end)

    case internet_host do
      nil -> AttackerState.new("internet")
      host -> AttackerState.new(host.id)
    end
  end

  defp default_rules do
    [%NetworkDefense.Rules.RemoteServiceExploitation{}]
  end

  defp broadcast_simulation_completed(experiment, correlation_id) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @simulation_events_topic,
      {:simulation_completed,
       %{
         correlation_id: correlation_id,
         graph_id: experiment.graph_id,
         experiment_id: experiment.id
       }}
    )
  end

  defp broadcast_simulation_failed(graph_id, correlation_id, reason) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @simulation_events_topic,
      {:simulation_failed,
       %{
         correlation_id: correlation_id,
         graph_id: graph_id,
         reason: reason
       }}
    )
  end
end
