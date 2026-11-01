defmodule NetworkDefense.Evaluation2.FinalAnalysisDAGTest do
  @moduledoc """
  Static topology of the Final analysis DAG.

  The DAG source is loaded here without the Gust runner, so the assertions cover
  the declared task order, the mapped comparison stage, the fan-in task, and the
  stored terminal output. The cases need no database and no clock process.

      mix test test/network_defense/evaluation2/final_analysis_dag_test.exs
  """

  use ExUnit.Case, async: false

  @moduletag :unit

  alias NetworkDefense.Evaluation2.Study.Workflow.FinalAnalysis.DAG

  @dag_file "gust/dags/evaluation2_study_final_analysis.ex"
  @terminal :correct_final_family

  # Load during serialized execution. A loader can compile this source while
  # the full suite compiles test modules, so compile-time loading can race it.
  setup_all do
    unless Code.ensure_loaded?(DAG) do
      Code.require_file(Path.join(:code.priv_dir(:network_defense), @dag_file))
    end

    :ok
  end

  test "tasks are declared in the prepare, mapped evaluate, and correct order" do
    assert task_names() == [:prepare_final_analysis, :evaluate_final_comparison, @terminal]
  end

  test "the preparation task stores the mapped job batch and opens the run" do
    options = options(:prepare_final_analysis)

    assert options[:downstream] == [:evaluate_final_comparison]
    assert options[:store_result] == true
    assert options[:map_over] == nil
  end

  test "one mapped evaluation task consumes the prepared batch" do
    options = options(:evaluate_final_comparison)

    assert options[:map_over] == :prepare_final_analysis
    assert options[:downstream] == [@terminal]
    assert options[:store_result] == true
  end

  test "the terminal task closes the run with a stored corrected family" do
    options = options(@terminal)

    assert options[:downstream] == nil
    assert options[:store_result] == true
    assert options[:map_over] == nil
    assert function_exported?(DAG, @terminal, 1)
  end

  test "the declared tasks form one chain from preparation to the terminal task" do
    downstreams = tasks() |> Map.values() |> Enum.flat_map(&Keyword.get(&1, :downstream, []))

    assert Enum.sort(downstreams) ==
             Enum.sort([:evaluate_final_comparison, @terminal])

    assert Enum.count(downstreams) == Enum.count(Enum.uniq(downstreams))
    assert Enum.count(tasks()) == 3
  end

  defp tasks do
    DAG.__dag_tasks__()
    |> Enum.reverse()
    |> Map.new()
  end

  defp task_names do
    DAG.__dag_tasks__() |> Enum.reverse() |> Enum.map(&elem(&1, 0))
  end

  defp options(name), do: Map.fetch!(tasks(), name)
end
