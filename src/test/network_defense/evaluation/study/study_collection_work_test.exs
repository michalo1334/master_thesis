defmodule NetworkDefense.Evaluation.Study.StudyCollectionWorkTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Evaluation.Pilot.Limits
  alias NetworkDefense.Evaluation.Study.Collection
  alias NetworkDefense.Evaluation.Study.CollectionLimits
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.StudyConformance
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}

  setup do
    restore_limits(Application.get_env(:network_defense, CollectionLimits))
    execution = execution()

    %{
      definition: StudyConformance.parsed!(),
      execution: execution,
      phase: phase(execution, :pilot_collection)
    }
  end

  test "COLLECTION-WORK-01: ordered side-and-plan work uses the first required seeds", %{
    definition: definition,
    execution: execution,
    phase: phase
  } do
    assert {:ok, items} = Collection.build_collection_work(execution, phase, definition, 0)

    assert Enum.count(items) == 24
    assert Enum.map(items, & &1.item_position) == Enum.to_list(0..23)

    assert Enum.map(items, &{&1.comparison_position, &1.side, &1.plan_position}) ==
             for(
               comparison_position <- 0..1,
               side <- [:alternative, :reference],
               plan_position <- 0..5,
               do: {comparison_position, side, plan_position}
             )

    seeds = [610_001, 610_002, 610_003, 610_004, 610_005, 610_006]

    assert Enum.map(items, & &1.selection_seed) == seeds ++ seeds ++ seeds ++ seeds

    assert strategy_keys(items, 0..5) == List.duplicate("simulation_informed", 6)
    assert strategy_keys(items, 6..11) == List.duplicate("cvss", 6)
    assert strategy_keys(items, 12..17) == List.duplicate("simulated_annealing", 6)
    assert strategy_keys(items, 18..23) == List.duplicate("cvss", 6)

    assert Enum.map(items, & &1.comparison.tier) ==
             List.duplicate("core", 12) ++ List.duplicate("edge", 12)

    assert Enum.map(items, & &1.budget) == List.duplicate(4, 12) ++ List.duplicate(6, 12)

    assert Enum.map(items, & &1.evaluation_root) ==
             List.duplicate(310_001, 12) ++ List.duplicate(310_002, 12)

    assert Enum.map(items, & &1.graph_revision_id) |> Enum.uniq() |> length() == 2
    assert Enum.all?(items, &(&1.replica_position == 0))
    assert Enum.all?(items, &(&1.attack_count == 12))
    assert Enum.all?(items, &(&1.iterations_per_run == 40 and &1.max_attempts == 12))

    assert {:ok, repeated} = Collection.build_collection_work(execution, phase, definition, 0)
    assert repeated == items

    assert {:ok, [%{replica_position: 1, item_position: 0} | _rest]} =
             Collection.build_collection_work(execution, phase, definition, 1)
  end

  test "COLLECTION-WORK-02: planned work above the phase item cap is rejected", %{
    definition: definition,
    execution: execution,
    phase: phase
  } do
    put_limits(max_phase_items: 24, max_gust_concurrency: 2)

    assert {:ok, items} = Collection.build_collection_work(execution, phase, definition, 0)
    assert Enum.count(items) == 24

    put_limits(max_phase_items: 23, max_gust_concurrency: 2)

    assert {:error, %StudyError{code: "validation_failed", issues: [issue]}} =
             Collection.build_collection_work(execution, phase, definition, 0)

    assert issue["code"] == "collection_work_limit_exceeded"
    assert issue["details"] == %{"limit" => 23, "actual" => 24}
  end

  test "COLLECTION-WORK-03: unavailable or invalid collection controls return one bounded error",
       %{
         definition: definition,
         execution: execution,
         phase: phase
       } do
    Application.delete_env(:network_defense, CollectionLimits)

    assert {:error, %StudyError{code: "unavailable", issues: [missing_issue]}} =
             Collection.build_collection_work(execution, phase, definition, 0)

    assert missing_issue["code"] == "configuration_invalid"

    assert {:ok, %Limits{}} = Limits.fetch()

    for config <- [
          [max_phase_items: 24],
          [max_phase_items: 24, max_gust_concurrency: 0],
          [max_phase_items: "many", max_gust_concurrency: 2]
        ] do
      Application.put_env(:network_defense, CollectionLimits, config)

      assert {:error, %StudyError{code: "unavailable", issues: [invalid_issue]}} =
               Collection.build_collection_work(execution, phase, definition, 0)

      assert invalid_issue["code"] == "configuration_invalid"
    end
  end

  test "COLLECTION-WORK-04: a Final phase is rejected instead of planned", %{
    definition: definition,
    execution: execution
  } do
    phase = phase(execution, :final_collection)

    assert {:error, %StudyError{code: "validation_failed", issues: [issue]}} =
             Collection.build_collection_work(execution, phase, definition, 0)

    assert issue["code"] == "unsupported_collection_phase"
  end

  test "COLLECTION-WORK-05: a foreign phase or an invalid replica is rejected", %{
    definition: definition,
    execution: execution,
    phase: phase
  } do
    foreign_phase = pilot_phase()

    assert {:error, %StudyError{issues: [phase_issue]}} =
             Collection.build_collection_work(execution, foreign_phase, definition, 0)

    assert phase_issue["code"] == "collection_phase_mismatch"

    for replica_position <- [-1, "zero", nil] do
      assert {:error, %StudyError{issues: [position_issue]}} =
               Collection.build_collection_work(execution, phase, definition, replica_position)

      assert position_issue["code"] == "invalid_collection_position"
      assert position_issue["path"] == ["replica_position"]
    end
  end

  test "COLLECTION-WORK-06: a selection pool smaller than the plan count is rejected", %{
    definition: definition,
    execution: execution,
    phase: phase
  } do
    short_seeds = %{
      definition
      | pilot: %{
          definition.pilot
          | collection: %{
              definition.pilot.collection
              | selection_seeds: Enum.take(definition.pilot.collection.selection_seeds, 4)
            }
        }
    }

    assert {:error, %StudyError{code: "validation_failed", issues: [issue]}} =
             Collection.build_collection_work(execution, phase, short_seeds, 0)

    assert issue["code"] == "incomplete_collection_definition"
    assert issue["path"] == ["pilot", "collection", "selection_seeds"]
  end

  defp strategy_keys(items, range),
    do: for(index <- range, do: Enum.at(items, index).strategy.key)

  defp execution do
    %StudyExecution{
      id: Ecto.UUID.generate(),
      study_revision_id: Ecto.UUID.generate(),
      state: :collecting_pilot
    }
  end

  defp pilot_phase, do: phase(execution(), :pilot_collection)

  defp phase(execution, name) do
    %StudyPhase{id: Ecto.UUID.generate(), execution_id: execution.id, phase: name}
  end

  defp put_limits(limits) do
    Application.put_env(:network_defense, CollectionLimits, limits)
  end

  defp restore_limits(original) do
    put_limits(original)

    ExUnit.Callbacks.on_exit(fn ->
      if original,
        do: Application.put_env(:network_defense, CollectionLimits, original),
        else: Application.delete_env(:network_defense, CollectionLimits)
    end)
  end
end
