defmodule NetworkDefense.Evaluation2.FinalTierCollectionActionsTest do
  @moduledoc """
  Transport and binding rules of the Final tier collection tasks.

  The cases cover the stored preparation result, the replica timing receipt, the
  five-receipt tier timing value, the tier and selection binding, and the
  re-read measured environment label. They need no database, no Gust run, and no
  clock process.

      mix test test/network_defense/evaluation2/final_tier_collection_actions_test.exs
  """

  use ExUnit.Case, async: false

  @moduletag :unit
  @moduletag case_id: "BIND-02"

  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Definition.Provenance
  alias NetworkDefense.Evaluation2.Study.Final.TierContract
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.{CollectionItem, PhaseRun}
  alias NetworkDefense.Evaluation2.Study.Randomness
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Selection

  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.{
    Boundary,
    CompleteTier,
    Prepared
  }

  @phase_run_id "5f0d1f7a-3b8f-4c62-9a41-1f2c9b4d7e10"
  @plan_id "a1b2c3d4-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
  @clock_session "8e7d6c5b-4a39-4281-9706-5d4e3c2b1a09"

  @prepared %Prepared{
    plan_id: @plan_id,
    clock_session: @clock_session,
    phase_run_id: @phase_run_id,
    tier: :medium
  }

  describe "stored preparation result" do
    test "round-trips through the task transport" do
      assert Boundary.prepared_params(@prepared) == %{
               "plan_id" => @plan_id,
               "clock_session" => @clock_session,
               "phase_run_id" => @phase_run_id,
               "tier" => "medium"
             }

      assert {:ok, decoded} = Boundary.decode_prepared(Boundary.prepared_params(@prepared))
      assert decoded == @prepared
    end

    test "rejects a result that does not name one canonical phase run and tier" do
      valid = Boundary.prepared_params(@prepared)

      refute_valid(Map.put(valid, "tier", "huge"))
      refute_valid(Map.put(valid, "tier", :medium))
      refute_valid(Map.put(valid, "plan_id", String.upcase(@plan_id)))
      refute_valid(Map.put(valid, "phase_run_id", "not-a-uuid"))
      refute_valid(Map.put(valid, "clock_session", ""))
      refute_valid(Map.delete(valid, "clock_session"))
      refute_valid(Map.put(valid, "plan_id", 42))
      refute_valid(Map.put(valid, "unexpected", 1))
      refute_valid("invalid")
    end
  end

  describe "replica timing receipt" do
    test "round-trips the measured durations of one replica" do
      replica = %Timing.Replica{plan_selection_us: 120, simulation_us: 480, total_us: 600}

      assert {:ok, {2, ^replica}} =
               Boundary.replica_params(2, replica) |> Boundary.decode_replica()
    end

    test "rejects a receipt without one measured replica coordinate" do
      valid = Boundary.replica_params(3, replica())

      refute_valid_receipt(Map.put(valid, "replica_position", -1))
      refute_valid_receipt(Map.put(valid, "replica_position", 5))
      refute_valid_receipt(Map.put(valid, "replica_position", "3"))
      refute_valid_receipt(Map.put(valid, "plan_selection_us", -1))
      refute_valid_receipt(Map.put(valid, "simulation_us", 1.5))
      refute_valid_receipt(Map.put(valid, "total_us", -1))
      refute_valid_receipt(Map.delete(valid, "total_us"))
      refute_valid_receipt(Map.put(valid, "unexpected", 1))
      refute_valid_receipt(:invalid)
    end
  end

  describe "tier timing of one run" do
    test "requires the five distinct measured replica receipts" do
      assert {:ok, %Timing.Tier{replicas: replicas}} =
               CompleteTier.replica_timing(receipts(0..4))

      assert Enum.sort(Map.keys(replicas)) == [0, 1, 2, 3, 4]
      assert replicas[3] == replica(3)
    end

    test "accepts receipts in any stored order" do
      assert CompleteTier.replica_timing(receipts(4..0//-1)) ==
               CompleteTier.replica_timing(receipts(0..4))
    end

    test "rejects a missing, repeated, or invalid receipt" do
      assert CompleteTier.replica_timing(receipts(0..3)) == {:error, :incomplete_timing}

      assert CompleteTier.replica_timing(receipts(0..3) ++ receipts(0..0)) ==
               {:error, :incomplete_timing}

      assert CompleteTier.replica_timing(receipts(0..3) ++ [:invalid]) ==
               {:error, :incomplete_timing}

      assert CompleteTier.replica_timing(receipts(0..4) ++ receipts(0..0)) ==
               {:error, :incomplete_timing}
    end

    test "the gathered receipts encode into the decodable tier output" do
      assert {:ok, timing} = CompleteTier.replica_timing(receipts(0..4))

      output = %TierContract.Output{
        phase_run_id: @phase_run_id,
        tier: :medium,
        clock_session: @clock_session,
        timing: timing
      }

      assert {:ok, params} = TierContract.encode_output(output)
      assert params["tier"] == "medium"
      assert TierContract.decode_output(params) == {:ok, output}
    end
  end

  describe "run binding" do
    test "the tier comes from the canonical phase-run key" do
      assert Boundary.expect_tier(%PhaseRun{run_key: :small}) == {:ok, :small}
      assert Boundary.expect_tier(%PhaseRun{run_key: :large}) == {:ok, :large}
      assert Boundary.expect_tier(%PhaseRun{run_key: :single}) == {:error, :unknown_tier}
    end

    test "a tier run requires the frozen Final selection" do
      selection = %Selection{candidate_id: "one", plan_count_per_side: 30, attacks_per_plan: 60}

      assert Boundary.expect_selection(%Persistence.Execution{selection: selection}) ==
               {:ok, selection}

      assert Boundary.expect_selection(%Persistence.Execution{selection: nil}) ==
               {:error, :missing_selection}
    end
  end

  describe "measured environment label" do
    setup do
      previous = Application.get_env(:network_defense, :measured_environment_revision)

      on_exit(fn ->
        Application.put_env(:network_defense, :measured_environment_revision, previous)
      end)
    end

    test "an unchanged configured label passes" do
      put_label("test-environment")

      assert Boundary.expect_environment(definition("test-environment")) == :ok
    end

    test "a changed configured label fails" do
      put_label("another-environment")

      assert Boundary.expect_environment(definition("test-environment")) ==
               {:error, :environment_changed}
    end

    test "a missing configured label fails" do
      put_label(nil)

      assert Boundary.expect_environment(definition("test-environment")) ==
               {:error, :environment_missing}
    end

    test "a definition frozen without a label fails" do
      put_label("test-environment")
      assert Boundary.expect_environment(definition(nil)) == {:error, :environment_missing}

      put_label(nil)
      assert Boundary.expect_environment(definition(nil)) == {:error, :environment_missing}
    end
  end

  test "WHEN known method or seed contracts change THEN Final re-entry SHALL fail" do
    current = %Definition{
      provenance: %Provenance{
        method: Definition.method(),
        seed_contract: Randomness.contract()
      }
    }

    assert :ok = Boundary.expect_contract(current)

    assert {:error, :incompatible_contract} =
             Boundary.expect_contract(%{
               current
               | provenance: %{current.provenance | method: "another-method"}
             })

    assert {:error, :incompatible_contract} =
             Boundary.expect_contract(%{
               current
               | provenance: %{current.provenance | seed_contract: "another-seed-contract"}
             })
  end

  describe "task coordinates" do
    test "measured positions and stored task names are the declared ones" do
      assert Boundary.measured_positions() == 0..4
      assert Boundary.replica_task(0) == "complete_replica_0"
      assert Boundary.replica_task(4) == "complete_replica_4"
    end

    test "the prepared item batch carries one identity per item" do
      items = [
        %CollectionItem{id: Ecto.UUID.generate(), item_position: 0},
        %CollectionItem{id: Ecto.UUID.generate(), item_position: 1}
      ]

      assert Boundary.item_params(items) ==
               Enum.map(items, &%{"collection_item_id" => &1.id})
    end
  end

  defp refute_valid(params) do
    assert Boundary.decode_prepared(params) == :error
  end

  defp refute_valid_receipt(params) do
    assert Boundary.decode_replica(params) == :error
  end

  defp receipts(positions) do
    Enum.map(positions, &Boundary.replica_params(&1, replica(&1)))
  end

  defp replica(position \\ 1) do
    plan_selection_us = 120 + 10 * position
    simulation_us = 480 + 20 * position

    %Timing.Replica{
      plan_selection_us: plan_selection_us,
      simulation_us: simulation_us,
      total_us: plan_selection_us + simulation_us
    }
  end

  defp definition(label) do
    %Definition{provenance: %Provenance{environment_label: label}}
  end

  defp put_label(label) do
    Application.put_env(:network_defense, :measured_environment_revision, label)
  end
end
