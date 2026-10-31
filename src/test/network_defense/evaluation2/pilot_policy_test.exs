defmodule NetworkDefense.Evaluation2.PilotPolicyTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.{Definition, Views}
  alias NetworkDefense.Evaluation2.Study.Persistence.Revision
  alias NetworkDefense.Evaluation2.Study.Pilot.{Analysis, Assessment}
  alias NetworkDefense.Evaluation2Test.FoundationFixtures

  @moduletag :unit
  @moduletag case_id: "PILOT-01/PILOT-02/FLOW-03/RESULT-01"

  setup do
    {:ok, definition} = Definition.parse(FoundationFixtures.valid_attrs())
    %{definition: definition}
  end

  test "PILOT-01 WHEN fan-in is incomplete or duplicated THEN selection SHALL reject it", c do
    assessments = assessments(c.definition, 0.04)
    costs = %{plan_ms: [4, 6], attack_ms: [0.1, 0.3]}
    assert {:error, _} = Analysis.summarize(c.definition, tl(assessments), costs)
    assert {:error, _} = Analysis.summarize(c.definition, [hd(assessments) | assessments], costs)
    [first | rest] = assessments

    assert {:error, _} =
             Analysis.summarize(c.definition, [%{first | passes: false} | rest], costs)
  end

  test "PILOT-02 WHEN candidates pass THEN selection SHALL count shared references once per budget",
       c do
    assert {:ok, output} =
             Analysis.summarize(c.definition, assessments(c.definition, 0.04), %{
               plan_ms: [4, 6],
               attack_ms: [0.1, 0.3]
             })

    assert output.outcome.outcome == :recommended
    assert output.outcome.candidate_id == "smaller"
    [small, large] = output.candidates
    # Three tiers times six unique groups in the largest tier. Median costs are
    # five ms per plan and 0.2 ms per attack; CVSS appears once per budget.
    assert_in_delta small.predicted_runtime_ms, 3 * 6 * 10 * (5 + 20 * 0.2), 1.0e-10
    assert_in_delta large.predicted_runtime_ms, 3 * 6 * 20 * (5 + 40 * 0.2), 1.0e-10
  end

  test "PILOT-02 WHEN none pass THEN the outcome SHALL explain insufficient precision", c do
    assert {:ok, output} =
             Analysis.summarize(c.definition, assessments(c.definition, 0.06), %{
               plan_ms: [0],
               attack_ms: [0]
             })

    assert output.outcome.outcome == :insufficient
    assert output.outcome.candidate_id == nil

    assert Enum.all?(output.candidates, fn candidate ->
             Enum.all?(candidate.comparisons, &(not &1.passes))
           end)
  end

  test "PILOT-02 WHEN predicted costs tie THEN more plans and fewer attacks SHALL win", c do
    attrs =
      put_in(FoundationFixtures.valid_attrs(), ["pilot", "candidates"], [
        %{"id" => "a", "plans" => 10, "attacks" => 40},
        %{"id" => "b", "plans" => 20, "attacks" => 20},
        %{"id" => "c", "plans" => 20, "attacks" => 40}
      ])

    {:ok, definition} = Definition.parse(attrs)

    assert {:ok, output} =
             Analysis.summarize(definition, assessments(definition, 0.04), %{
               plan_ms: [0],
               attack_ms: [0]
             })

    assert output.outcome.candidate_id == "b"
    assert c.definition.pilot.precision.target_half_width == 0.05
  end

  test "FLOW-03 WHEN timeout is invalid THEN continue SHALL return a validation error" do
    assert {:error, %{category: :validation_failed}} =
             Study.continue(Ecto.UUID.generate(), timeout: -1)
  end

  test "RESULT-01 WHEN a comparison position leaves the declaration THEN report construction SHALL stay bounded",
       c do
    {:ok, output} =
      Analysis.summarize(c.definition, assessments(c.definition, 0.04), %{
        plan_ms: [0],
        attack_ms: [0]
      })

    [candidate | rest] = output.candidates
    [comparison | remaining] = candidate.comparisons

    corrupted = %{
      output
      | candidates: [
          %{candidate | comparisons: [%{comparison | comparison_position: 999} | remaining]}
          | rest
        ]
    }

    assert {:error, _} = Analysis.validate_output(c.definition, corrupted)
    revision = %Revision{definition: c.definition}
    assert {:error, _} = Views.pilot_result(revision, corrupted)
  end

  defp assessments(definition, width) do
    for {_candidate, candidate_position} <- Enum.with_index(definition.pilot.candidates),
        {_comparison, comparison_position} <- Enum.with_index(Definition.comparisons(definition)) do
      %Assessment{
        candidate_position: candidate_position,
        comparison_position: comparison_position,
        guarded_half_width: width,
        informative: true,
        passes: width <= definition.pilot.precision.target_half_width
      }
    end
  end
end
