defmodule NetworkDefense.Evaluation2.FinalTierCollectionLoadTest do
  @moduledoc """
  Load check of the Final tier collection DAG.

  Gust parses the DAG source and links its declared tasks, so a load proves that
  the source, the action modules, the mapped stages, and the downstream chain are
  acceptable to the runner. The case needs the isolated local test database for
  the Gust DAG rows.

      mix test test/network_defense/evaluation2/final_tier_collection_load_test.exs
  """

  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.DAG.Definition
  alias Gust.DAG.Loader.Worker, as: DAGLoader
  alias Gust.Flows

  @moduletag :integration
  @moduletag case_id: "BIND-02"

  @dag_name "evaluation2_study_final_tier_collection"
  @measured_positions 0..4

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    start_supervised!({DAGLoader, %{dags_folder: Application.fetch_env!(:gust, :dags_folder)}})

    # The synchronous read follows the loader's bootstrap continuation.
    DAGLoader.get_definitions()
    :ok
  end

  test "the Final tier DAG loads as one sequential replica chain" do
    dag = Flows.get_dag_by_name(@dag_name)
    assert %Flows.Dag{id: dag_id} = dag

    assert {:ok, %Definition{} = definition} = DAGLoader.get_definition(dag_id)
    assert Definition.empty_errors?(definition)

    tasks = definition.tasks
    assert map_size(tasks) == 35
    assert downstream(tasks, "prepare_tier_collection") == ["prepare_warm_up_replica"]
    assert downstream(tasks, "run_warm_up_simulation") == ["prepare_replica_0"]

    for position <- @measured_positions do
      prepare = "prepare_replica_#{position}"

      assert downstream(tasks, prepare) == ["mark_plan_start_#{position}"]

      assert mapped_over(tasks, "run_optimization_#{position}") == prepare
      assert mapped_over(tasks, "run_simulation_#{position}") == prepare

      assert downstream(tasks, "run_simulation_#{position}") == [
               "complete_replica_#{position}"
             ]

      assert tasks[prepare][:store_result] == true
      assert tasks["complete_replica_#{position}"][:store_result] == true
    end

    assert downstream(tasks, "complete_replica_4") == ["complete_final_tier_collection"]
    assert downstream(tasks, "complete_final_tier_collection") == []
    assert tasks["complete_final_tier_collection"][:store_result] == true
  end

  defp downstream(tasks, name) do
    tasks |> Map.fetch!(name) |> Map.fetch!(:downstream) |> Enum.sort()
  end

  defp mapped_over(tasks, name) do
    tasks |> Map.fetch!(name) |> Map.fetch!(:map_over) |> to_string()
  end
end
