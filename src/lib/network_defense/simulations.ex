defmodule NetworkDefense.Simulations do
  @moduledoc """
  Public context module for working with simulation related aspects
  """
  alias NetworkDefense.AttackerState.AttackerState
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.MultiState
  alias NetworkDefense.Simulation.MultiStates
  alias NetworkDefense.Simulation.Simulator
  alias NetworkDefense.Simulation.States

  import Ecto.Query

  require Logger

  def run(opts \\ []) do
    state = Simulator.run(opts)
    {:ok, saved} = States.insert(state)
    saved
  end

  def run_multiple(opts \\ []) do
    {multi_state, _states} = Simulator.run_multiple(opts)
    {:ok, saved} = MultiStates.insert(multi_state)
    saved
  end

  @simulation_events_topic "simulation_events"

  def simulation_events_topic, do: @simulation_events_topic

  def run_async(graph, correlation_id) do
    rules = default_rules()

    Task.start(fn ->
      try do
        {elapsed_us, {multi_state, states}} =
          :timer.tc(fn ->
            Simulator.run_multiple(
              graph: graph,
              initial_attacker_state: initial_attacker_state(graph),
              lock_version: graph.lock_version,
              rules: rules
            )
          end)

        runtime_ms = div(elapsed_us, 1000)

        multi_state = %{
          multi_state
          | runtime_ms: runtime_ms,
            lock_version: graph.lock_version,
            simulation_count: length(states)
        }

        case MultiStates.insert(multi_state) do
          {:ok, saved} ->
            Logger.info("simulation persisted: #{saved.id} for graph #{saved.graph_id}")

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

  def list_runs(graph_ids) when is_list(graph_ids) do
    query =
      from ms in MultiState,
        where: ms.graph_id in ^graph_ids,
        order_by: [desc: :inserted_at],
        preload: [:graph]

    Repo.all(query)
  end

  def list_runs(graph_ids), do: list_runs([graph_ids])

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

  defp broadcast_simulation_completed(simulation, correlation_id) do
    Phoenix.PubSub.broadcast(
      NetworkDefense.PubSub,
      @simulation_events_topic,
      {:simulation_completed,
       %{
         correlation_id: correlation_id,
         graph_id: simulation.graph_id,
         simulation_id: simulation.id
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
