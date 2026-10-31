defmodule NetworkDefense.Evaluation2Test.FinalFixtures do
  @moduledoc false

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.{Evidence, Persistence, PilotOutcome}
  alias NetworkDefense.Evaluation2.Study.Persistence.Executions
  alias NetworkDefense.Evaluation2Test.{FoundationFixtures, GraphFixtures}

  # Focused Final cases enter through existing transaction owners. They do not
  # claim that their synthetic Pilot receipt is a real Pilot execution.
  def approved_context do
    attrs =
      GraphFixtures.insert_tiers()
      |> GraphFixtures.document_opts()
      |> FoundationFixtures.valid_attrs()
      |> put_in(["study", "id"], "final-#{System.unique_integer([:positive])}")
      |> put_in(["pilot", "candidates"], [%{"id" => "tiny", "plans" => 1, "attacks" => 2}])
      |> put_in(["pilot", "extra_pool"], %{"plans" => 0, "attacks" => 0})
      |> put_in(["pilot", "precision", "outer_subsamples"], 2)
      |> put_in(["simulation", "iterations_per_run"], 2)
      |> put_in(["defense", "feasibility"], "unrestricted")
      |> update_in(["tiers"], fn tiers ->
        Map.new(tiers, fn {tier, value} ->
          {tier, %{value | "budgets" => [1], "alternatives" => [%{"strategy" => "random"}]}}
        end)
      end)

    {:ok, revision} = Study.create_revision(Jason.encode!(attrs))
    {:ok, pilot} = Executions.start_execution(revision)

    {:ok, _snapshot} =
      Persistence.insert_evidence_snapshot(pilot.active_phase.id, %Evidence{comparisons: []})

    {:ok, analysis} = Executions.accept_pilot_collection(pilot.active_phase.id)

    {:ok, gate} =
      Executions.accept_pilot_analysis(analysis.active_phase.id, %PilotOutcome{
        outcome: :insufficient
      })

    {:ok, final} = Executions.accept_approval(gate.execution.id, {:override_insufficient, "tiny"})
    final
  end
end
