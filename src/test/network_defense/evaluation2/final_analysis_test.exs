defmodule NetworkDefense.Evaluation2.FinalAnalysisTest do
  use NetworkDefense.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias NetworkDefense.Evaluation2.Study.{Definition, Evidence, Persistence, Randomness}
  alias NetworkDefense.Evaluation2.Study.Final.{Analysis, ComparisonJob}
  alias NetworkDefense.Evaluation2.Study.Persistence.Executions
  alias NetworkDefense.Evaluation2Test.{FinalFixtures, NumericAnchors}
  alias NetworkDefense.Simulation.Seed

  @moduletag :integration
  @moduletag case_id: "NUM-01/NUM-06/HOLM-01/RESULT-01"

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    previous = Application.get_env(:network_defense, :measured_environment_revision)
    Application.put_env(:network_defense, :measured_environment_revision, "final-analysis-test")

    on_exit(fn ->
      Sandbox.stop_owner(owner)

      if previous,
        do: Application.put_env(:network_defense, :measured_environment_revision, previous),
        else: Application.delete_env(:network_defense, :measured_environment_revision)
    end)

    context = FinalFixtures.approved_context()
    %{context: context, evidence: evidence(context)}
  end

  test "RESULT-01 WHEN Final evidence is prepared but unaccepted THEN scientific jobs SHALL be unavailable",
       c do
    {:ok, snapshot} = Persistence.insert_evidence_snapshot(c.context.active_phase.id, c.evidence)
    assert {:error, _} = Analysis.prepare(snapshot.id)
    {:ok, _accepted} = Executions.accept_final_collection(c.context.active_phase.id)
    assert {:ok, jobs} = Analysis.prepare(snapshot.id)
    assert Enum.map(jobs, & &1.comparison_position) == [0, 1, 2]
  end

  test "NUM-01/NUM-06 WHEN accepted matrices are evaluated THEN typed statistics SHALL use frozen model units",
       c do
    snapshot = accepted(c)
    assert {:ok, jobs} = Analysis.prepare(snapshot.id)

    for job <- jobs do
      assert {:ok, statistics} = Analysis.evaluate(snapshot.id, job)
      position = job.comparison_position
      declared = Enum.at(Definition.comparisons(c.context.revision.definition), position)
      graph = Enum.find(c.context.revision.definition.tiers, &(&1.tier == declared.tier))
      observed = Enum.at(c.evidence.comparisons, position)
      bound = graph.mission_impact_bound

      expected =
        NumericAnchors.reference_compare(
          observed.alternative,
          observed.reference,
          bound.minimum,
          bound.maximum,
          c.context.revision.definition.analysis.confidence_level
        )

      assert statistics.method == :matching_bounded_mean_v1
      assert statistics.estimate.contrast == :alternative_minus_reference
      assert_in_delta statistics.estimate.value, expected.estimate, 1.0e-12
      assert_in_delta statistics.interval.lower, expected.lower, 1.0e-8
      assert_in_delta statistics.interval.upper, expected.upper, 1.0e-8
      assert_in_delta statistics.test.raw_p_value, expected.p_value, 1.0e-12
      assert statistics.test.method == :sign_conservative_betting
      assert statistics.test.alternative == :two_sided
      assert statistics.assessment.status == :informative
      assert statistics.assessment.warnings == []
    end

    assert {:error, _} = Analysis.evaluate(snapshot.id, %ComparisonJob{comparison_position: -1})
    assert {:error, _} = Analysis.evaluate(snapshot.id, %ComparisonJob{comparison_position: 3})
  end

  test "HOLM-01 WHEN a complete canonical family arrives THEN correction SHALL retain order and inclusive decisions",
       c do
    snapshot = accepted(c)
    {:ok, jobs} = Analysis.prepare(snapshot.id)

    statistics =
      Enum.map(jobs, fn job ->
        {:ok, value} = Analysis.evaluate(snapshot.id, job)
        value
      end)

    raw = [0.01, 0.025, 0.8]

    statistics =
      Enum.zip_with(statistics, raw, fn value, p ->
        %{value | test: %{value.test | raw_p_value: p}}
      end)

    assert {:ok, output} = Analysis.correct(snapshot.id, statistics)
    assert Enum.map(output.family_result.comparisons, & &1.statistics) == statistics

    assert Enum.map(output.family_result.comparisons, & &1.adjustment.adjusted_p_value) == [
             0.03,
             0.05,
             0.8
           ]

    assert Enum.map(output.family_result.comparisons, & &1.adjustment.reject_null) == [
             true,
             true,
             false
           ]

    definition = c.context.revision.definition
    assert :ok = Analysis.validate_output(definition, output)

    for provenance <- [
          %{definition.provenance | method: "foreign-method"},
          %{definition.provenance | seed_contract: "foreign-seeds"}
        ] do
      assert {:error, _} =
               Analysis.validate_output(%{definition | provenance: provenance}, output)
    end

    [first | rest] = output.family_result.comparisons
    bad = %{first | adjustment: %{first.adjustment | reject_null: false}}

    refute Analysis.validate_output(c.context.revision.definition, %{
             output
             | family_result: %{output.family_result | comparisons: [bad | rest]}
           }) == :ok

    assert {:error, _} = Analysis.correct(snapshot.id, tl(statistics))
    assert {:error, _} = Analysis.correct(snapshot.id, statistics ++ [hd(statistics)])
    [head | tail] = statistics

    assert {:error, _} =
             Analysis.correct(snapshot.id, [
               %{head | test: %{head.test | raw_p_value: 1.1}} | tail
             ])

    assert {:error, _} =
             Analysis.correct(snapshot.id, [
               %{head | interval: %{head.interval | confidence_level: 0.8}} | tail
             ])
  end

  test "NUM-06 WHEN stored evidence has foreign seeds, dimensions, or outcomes THEN analysis SHALL reject it",
       c do
    [first | rest] = c.evidence.comparisons

    for changed <- [
          %{first | attack_seeds: [1, 2]},
          %{first | alternative: [[0.0]]},
          %{first | reference: [[-1.0, -1.0]]}
        ] do
      # Each immutable snapshot gets its own execution; accepted evidence is never overwritten.
      context = FinalFixtures.approved_context()
      original = evidence(context)
      [own | others] = original.comparisons

      changed = %{
        changed
        | attack_seeds:
            if(changed.attack_seeds == first.attack_seeds,
              do: own.attack_seeds,
              else: changed.attack_seeds
            )
      }

      {:ok, snapshot} =
        Persistence.insert_evidence_snapshot(context.active_phase.id, %{
          original
          | comparisons: [changed | others]
        })

      {:ok, _} = Executions.accept_final_collection(context.active_phase.id)
      assert {:error, _} = Analysis.evaluate(snapshot.id, %ComparisonJob{comparison_position: 0})
    end

    assert rest != []
  end

  test "NUM-06 WHEN the configured environment changes THEN Final analysis SHALL reject re-entry",
       c do
    snapshot = accepted(c)
    Application.put_env(:network_defense, :measured_environment_revision, "changed")
    assert {:error, _} = Analysis.prepare(snapshot.id)
    assert {:error, _} = Analysis.evaluate(snapshot.id, %ComparisonJob{comparison_position: 0})
  end

  defp accepted(c) do
    {:ok, snapshot} = Persistence.insert_evidence_snapshot(c.context.active_phase.id, c.evidence)
    {:ok, _context} = Executions.accept_final_collection(c.context.active_phase.id)
    snapshot
  end

  defp evidence(context) do
    definition = context.revision.definition

    %Evidence{
      comparisons:
        Enum.map(Definition.comparisons(definition), fn comparison ->
          tier = Enum.find(definition.tiers, &(&1.tier == comparison.tier))
          bound = tier.mission_impact_bound
          low = bound.minimum / 1
          high = bound.maximum / 1
          root = Randomness.evaluation_root(definition, :final, comparison.tier)

          %Evidence.Comparison{
            attack_seeds:
              Enum.map(
                1..context.execution.selection.attacks_per_plan,
                &Seed.child_seed(root, &1)
              ),
            alternative: [[low, high]],
            reference: [[high, high]]
          }
        end)
    }
  end
end
