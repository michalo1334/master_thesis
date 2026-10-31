defmodule NetworkDefense.Evaluation2.Study.Pilot.Analysis do
  @moduledoc """
  Pilot numerical assessments and complete-family candidate selection.

  Widths and targets use frozen-model outcome units. The finite-pool precision
  guard is a planning heuristic for independent future Final observations.

  Every candidate must pass every comparison. Rank passing candidates by the
  observed-cost heuristic, then larger plan count, smaller attack count and
  earlier declaration. Shared physical groups count CVSS once per budget.
  Both recommendation and insufficiency require explicit operator approval.
  """

  alias NetworkDefense.Evaluation2.Study.{
    Compute,
    Definition,
    Error,
    Persistence,
    PilotOutcome,
    Randomness
  }

  alias NetworkDefense.Evaluation2.Study.Compute.PilotPrecision
  alias NetworkDefense.Evaluation2.Study.Persistence.Collection, as: Store
  alias NetworkDefense.Evaluation2.Study.Pilot.{AnalysisContract, Assessment, Job, Summary}
  alias NetworkDefense.Evaluation2.Study.Views

  @doc "Prepare all declared candidate/comparison jobs from the owning Pilot snapshot."
  @spec prepare(Ecto.UUID.t()) :: {:ok, [Job.t()]} | {:error, Error.t()}
  def prepare(snapshot_id) do
    with {:ok, context} <- context(snapshot_id) do
      definition = context.revision.definition

      {:ok,
       for {_candidate, candidate_position} <- Enum.with_index(definition.pilot.candidates),
           {comparison, comparison_position} <-
             Enum.with_index(Definition.comparisons(definition)) do
         %Job{
           candidate_position: candidate_position,
           comparison_position: comparison_position,
           stream_seed: Randomness.pilot_planning_seed(definition, comparison)
         }
       end}
    end
  end

  @doc "Assess one candidate using shared-prefix subsets and the frozen precision target."
  @spec evaluate(Ecto.UUID.t(), Job.t()) :: {:ok, Assessment.t()} | {:error, Error.t()}
  def evaluate(snapshot_id, %Job{candidate_position: cp, comparison_position: jp} = job)
      when is_integer(cp) and cp >= 0 and is_integer(jp) and jp >= 0 do
    with {:ok, context} <- context(snapshot_id),
         definition = context.revision.definition,
         {:ok, candidate} <- Enum.fetch(definition.pilot.candidates, cp),
         {:ok, comparison} <- Enum.fetch(Definition.comparisons(definition), jp),
         {:ok, evidence} <- Enum.fetch(context.snapshot.evidence.comparisons, jp),
         true <- job.stream_seed == Randomness.pilot_planning_seed(definition, comparison),
         tier = Enum.find(definition.tiers, &(&1.tier == comparison.tier)),
         bound = tier.mission_impact_bound,
         input = %{
           alternative: evidence.alternative,
           reference: evidence.reference,
           lower_bound: bound.minimum,
           upper_bound: bound.maximum
         },
         {:ok, result} <-
           Compute.pilot_precision(
             input,
             candidate,
             definition.pilot.precision,
             definition.analysis,
             job.stream_seed
           ) do
      {:ok,
       %Assessment{
         candidate_position: cp,
         comparison_position: jp,
         guarded_half_width: result.guarded_half_width,
         informative: result.informative,
         passes:
           result.informative and
             result.guarded_half_width <= definition.pilot.precision.target_half_width
       }}
    else
      {:error, %Error{}} = error -> error
      _invalid -> invalid_input()
    end
  end

  def evaluate(_snapshot_id, _job), do: invalid_input()

  @doc "Validate complete assessments and select a recommendation or explicit insufficiency."
  @spec decide(Ecto.UUID.t(), [Assessment.t()]) ::
          {:ok, AnalysisContract.Output.t()} | {:error, Error.t()}
  def decide(snapshot_id, assessments) do
    with {:ok, context} <- context(snapshot_id),
         {:ok, phase_run} <- Persistence.fetch_phase_run(context.phase.id, :single),
         {:ok, samples} <- Store.runtime_samples(phase_run.id) do
      summarize(context.revision.definition, assessments, samples)
    else
      {:error, %Persistence.Error{} = error} -> {:error, Views.error(error)}
      error -> error
    end
  end

  @doc "Check complete fan-in and rank passing candidates with the fixed cost heuristic."
  @spec summarize(Definition.t(), [Assessment.t()], map()) ::
          {:ok, AnalysisContract.Output.t()} | {:error, Error.t()}
  def summarize(definition, assessments, %{plan_ms: plans, attack_ms: attacks}) do
    with :ok <- complete_assessments(definition, assessments),
         true <- valid_costs?(plans) and valid_costs?(attacks) do
      costs = {PilotPrecision.quantile(plans, 0.5), PilotPrecision.quantile(attacks, 0.5)}

      summaries =
        definition.pilot.candidates
        |> Enum.with_index()
        |> Enum.map(&summary(&1, definition, assessments, costs))

      {:ok, %AnalysisContract.Output{outcome: outcome(summaries), candidates: summaries}}
    else
      _invalid -> invalid_input()
    end
  end

  def summarize(_definition, _assessments, _costs), do: invalid_input()

  @doc "Check the complete persisted terminal output against the frozen declaration."
  @spec validate_output(Definition.t(), AnalysisContract.Output.t()) :: :ok | {:error, Error.t()}
  def validate_output(definition, %AnalysisContract.Output{
        candidates: summaries,
        outcome: accepted
      })
      when is_list(summaries) do
    valid? =
      length(summaries) == length(definition.pilot.candidates) and
        Enum.all?(
          Enum.zip(Enum.with_index(definition.pilot.candidates), summaries),
          &valid_summary?(&1, definition)
        )

    if valid? and accepted == outcome(summaries), do: :ok, else: invalid_input()
  end

  def validate_output(_definition, _output), do: invalid_input()

  defp valid_summary?({{candidate, position}, %Summary{} = summary}, definition) do
    summary.candidate_position == position and summary.candidate_id == candidate.id and
      summary.plan_count_per_side == candidate.plans and
      summary.attacks_per_plan == candidate.attacks and
      valid_cost?(summary.predicted_runtime_ms) and
      complete_candidate?(summary.comparisons, position, definition)
  end

  defp valid_summary?(_pair, _definition), do: false

  defp complete_candidate?(comparisons, position, definition) when is_list(comparisons) do
    assessments =
      Enum.map(comparisons, fn c ->
        %Assessment{
          candidate_position: position,
          comparison_position: c.comparison_position,
          guarded_half_width: c.guarded_half_width,
          informative: c.informative,
          passes: c.passes
        }
      end)

    expected = Enum.to_list(0..(length(Definition.comparisons(definition)) - 1))

    Enum.map(assessments, & &1.comparison_position) == expected and
      Enum.all?(assessments, &valid_assessment?(&1, definition.pilot.precision.target_half_width))
  end

  defp complete_candidate?(_comparisons, _position, _definition), do: false

  defp complete_assessments(definition, assessments) when is_list(assessments) do
    expected =
      for {_candidate, cp} <- Enum.with_index(definition.pilot.candidates),
          {_comparison, jp} <- Enum.with_index(Definition.comparisons(definition)),
          do: {cp, jp}

    valid? =
      Enum.all?(assessments, &valid_assessment?(&1, definition.pilot.precision.target_half_width))

    positions =
      Enum.map(
        assessments,
        &{Map.get(&1, :candidate_position), Map.get(&1, :comparison_position)}
      )

    if valid? and Enum.sort(positions) == Enum.sort(expected), do: :ok, else: invalid_input()
  end

  defp complete_assessments(_definition, _assessments), do: invalid_input()

  defp valid_assessment?(%Assessment{} = assessment, target) do
    valid_cost?(assessment.guarded_half_width) and is_boolean(assessment.informative) and
      is_boolean(assessment.passes) and
      assessment.passes == (assessment.informative and assessment.guarded_half_width <= target)
  end

  defp valid_assessment?(_assessment, _target), do: false
  defp valid_costs?([_ | _] = values), do: Enum.all?(values, &valid_cost?/1)
  defp valid_costs?(_values), do: false

  defp valid_cost?(value),
    do: is_number(value) and value >= 0 and value <= 1.797_693_134_862_315_7e308

  defp summary({candidate, position}, definition, assessments, {plan_ms, attack_ms}) do
    groups = Definition.collection_groups(definition) |> Enum.frequencies_by(& &1.tier)
    group_factor = length(definition.tiers) * Enum.max(Map.values(groups))

    comparisons =
      assessments
      |> Enum.filter(&(&1.candidate_position == position))
      |> Enum.sort_by(& &1.comparison_position)
      |> Enum.map(fn a ->
        %Summary.Comparison{
          comparison_position: a.comparison_position,
          guarded_half_width: a.guarded_half_width,
          informative: a.informative,
          passes: a.passes
        }
      end)

    %Summary{
      candidate_position: position,
      candidate_id: candidate.id,
      plan_count_per_side: candidate.plans,
      attacks_per_plan: candidate.attacks,
      predicted_runtime_ms:
        group_factor * candidate.plans *
          (plan_ms + candidate.attacks * attack_ms),
      comparisons: comparisons
    }
  end

  defp outcome(summaries) do
    selected =
      summaries
      |> Enum.filter(&Summary.passes?/1)
      |> Enum.min_by(&selection_key/1, fn -> nil end)

    case selected do
      nil ->
        %PilotOutcome{outcome: :insufficient}

      candidate ->
        %PilotOutcome{
          outcome: :recommended,
          candidate_id: candidate.candidate_id,
          plan_count_per_side: candidate.plan_count_per_side,
          attacks_per_plan: candidate.attacks_per_plan
        }
    end
  end

  defp selection_key(candidate),
    do:
      {candidate.predicted_runtime_ms, -candidate.plan_count_per_side, candidate.attacks_per_plan,
       candidate.candidate_position}

  defp context(snapshot_id) do
    case Persistence.fetch_evidence_context(snapshot_id) do
      {:ok,
       %{
         phase: %{phase: :pilot_collection},
         revision: %{definition: definition},
         snapshot: %{evidence: %{comparisons: evidence}}
       }} = result ->
        if length(evidence) == length(Definition.comparisons(definition)),
          do: result,
          else: invalid_input()

      {:ok, _context} ->
        invalid_input()

      {:error, error} ->
        {:error, Views.error(error)}
    end
  end

  defp invalid_input do
    {:error,
     %Error{
       category: :unavailable,
       issues: [
         %Error.Issue{
           code: "invalid_pilot_analysis_input",
           path: [],
           message: "Pilot analysis input is invalid."
         }
       ]
     }}
  end
end
