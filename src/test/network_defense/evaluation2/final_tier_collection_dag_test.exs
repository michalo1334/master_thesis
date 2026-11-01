defmodule NetworkDefense.Evaluation2.FinalTierCollectionDAGTest do
  @moduledoc """
  Static topology of the Final tier collection DAG.

  The DAG source is loaded here without the Gust runner, so the assertions cover
  the declared task order, the sequential replica chain, the mapped effect
  stages, and the stored terminal receipt. The cases need no database and no
  clock process.

      mix test test/network_defense/evaluation2/final_tier_collection_dag_test.exs
  """

  use ExUnit.Case, async: true

  @moduletag :unit

  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.DAG

  @dag_file "gust/dags/evaluation2_study_final_tier_collection.ex"
  @terminal :complete_final_tier_collection
  @measured_positions 0..4

  # The DAG source lives outside the compiled library, so the test file loads it
  # before it declares the cases that read the declared task list.
  unless Code.ensure_loaded?(DAG) do
    Code.require_file(Path.join(:code.priv_dir(:network_defense), @dag_file))
  end

  test "tasks are declared in the sequential warm-up and replica order" do
    assert task_names() == expected_order()
  end

  test "the preparation task opens the run and the terminal task closes it" do
    tasks = tasks()

    assert options(tasks, :prepare_tier_collection)[:downstream] == [:prepare_warm_up_replica]
    assert options(tasks, :prepare_tier_collection)[:store_result] == true

    assert options(tasks, @terminal)[:downstream] == nil
    assert options(tasks, @terminal)[:store_result] == true
    assert function_exported?(DAG, @terminal, 1)
  end

  test "the warm-up replica runs the scientific work without a stored receipt" do
    tasks = tasks()

    assert options(tasks, :prepare_warm_up_replica)[:downstream] == [:run_warm_up_optimization]
    assert options(tasks, :prepare_warm_up_replica)[:store_result] == true
    refute options(tasks, :run_warm_up_optimization)[:store_result]
    refute options(tasks, :run_warm_up_simulation)[:store_result]
    refute Map.has_key?(tasks, :complete_replica_warm_up)
  end

  test "every measured replica repeats the marked plan and simulation stages" do
    tasks = tasks()

    for position <- @measured_positions do
      prepare = task(:prepare_replica_, position)
      plan_start = task(:mark_plan_start_, position)
      optimization = task(:run_optimization_, position)
      simulation_start = task(:mark_simulation_start_, position)
      simulation = task(:run_simulation_, position)
      complete = task(:complete_replica_, position)

      assert options(tasks, prepare)[:downstream] == [plan_start]
      assert options(tasks, prepare)[:store_result] == true

      assert options(tasks, plan_start)[:downstream] == [optimization]
      refute options(tasks, plan_start)[:store_result]

      assert options(tasks, optimization)[:map_over] == prepare
      assert options(tasks, optimization)[:downstream] == [simulation_start]

      assert options(tasks, simulation_start)[:downstream] == [simulation]
      refute options(tasks, simulation_start)[:store_result]

      assert options(tasks, simulation)[:map_over] == prepare
      assert options(tasks, simulation)[:downstream] == [complete]

      assert options(tasks, complete)[:store_result] == true
      assert options(tasks, complete)[:downstream] == [next_task(position)]
    end
  end

  test "one prepared replica batch feeds both mapped effect stages" do
    tasks = tasks()

    for position <- @measured_positions do
      prepare = task(:prepare_replica_, position)
      mapped = Enum.filter(task_names(), &(options(tasks, &1)[:map_over] == prepare))

      assert mapped == [task(:run_optimization_, position), task(:run_simulation_, position)]
    end
  end

  test "the declared tasks form one static chain" do
    tasks = tasks()
    downstreams = tasks |> Map.values() |> Enum.flat_map(&Keyword.get(&1, :downstream, []))

    assert Enum.sort(downstreams) == Enum.sort(task_names() -- [:prepare_tier_collection])
    assert Enum.count(downstreams) == Enum.count(Enum.uniq(downstreams))
  end

  defp tasks do
    DAG.__dag_tasks__()
    |> Enum.reverse()
    |> Map.new()
  end

  defp task_names do
    DAG.__dag_tasks__() |> Enum.reverse() |> Enum.map(&elem(&1, 0))
  end

  defp options(tasks, name), do: Map.fetch!(tasks, name)

  defp expected_order do
    [:prepare_tier_collection, :prepare_warm_up_replica, :run_warm_up_optimization] ++
      [:run_warm_up_simulation] ++
      Enum.flat_map(@measured_positions, &replica_order/1) ++ [@terminal]
  end

  defp replica_order(position) do
    [
      task(:prepare_replica_, position),
      task(:mark_plan_start_, position),
      task(:run_optimization_, position),
      task(:mark_simulation_start_, position),
      task(:run_simulation_, position),
      task(:complete_replica_, position)
    ]
  end

  defp next_task(4), do: @terminal
  defp next_task(position), do: task(:prepare_replica_, position + 1)

  defp task(prefix, position), do: :"#{prefix}#{position}"
end
