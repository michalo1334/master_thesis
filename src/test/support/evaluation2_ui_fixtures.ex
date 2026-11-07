defmodule NetworkDefense.Evaluation2Test.UiFixtures do
  @moduledoc false
  alias Gust.Flows
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.{Collection, Definition, Persistence}
  alias NetworkDefense.Evaluation2Test.{FoundationFixtures, GraphFixtures}

  # Small explicit settings for UI checks. These are test inputs, not research defaults.
  def attrs(study_id \\ "ui-test") do
    GraphFixtures.insert_tiers()
    |> GraphFixtures.document_opts()
    |> FoundationFixtures.valid_attrs()
    |> put_in(["study", "id"], study_id)
    |> put_in(["seed"], 9_007_199_254_740_993)
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
  end

  def collection_context(attrs) do
    {:ok, parsed} = Definition.parse(attrs)
    {:ok, definition} = Definition.resolve(parsed)
    {:ok, identity} = Study.create_revision_from_params(attrs)
    {:ok, context} = Persistence.Executions.start_execution(identity)
    id = Ecto.UUID.generate()

    dag =
      Flows.get_dag_by_name("evaluation2_study_pilot_collection") ||
        elem(Flows.create_dag(%{name: "evaluation2_study_pilot_collection"}), 1)

    {:ok, gust_run} =
      Flows.create_run(%{dag_id: dag.id, params: %{"study_phase_run_id" => id}})

    {:ok, run} = Persistence.link_phase_run(context.active_phase.id, :single, id, gust_run.id)
    {:ok, plan} = Collection.prepare_pilot(run.id, definition)
    {:ok, items} = Collection.prepare_replica(plan.id, 0)
    %{context: context, run: run, plan: plan, items: items, definition: definition}
  end
end
