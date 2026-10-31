defmodule NetworkDefense.Evaluation2.Study.Final.Analysis do
  @moduledoc """
  Native Final comparisons and complete-family Holm correction.

  Jobs use canonical comparison positions. Accepted evidence owns the logical
  row and attack-column order; timing replicas never add scientific samples.
  Intervals are pointwise under the declared IID-input model. Pilot selection
  freezes the counts before this fresh Final evidence is collected.
  """

  alias NetworkDefense.Evaluation2.Study.{
    Compute,
    Definition,
    Error,
    Persistence,
    Randomness,
    Views
  }

  alias NetworkDefense.Evaluation2.Study.Final.{AnalysisContract, ComparisonJob, CorrectedFamily}
  alias NetworkDefense.Evaluation2.Study.Result.Comparison
  alias NetworkDefense.Simulation.Seed

  @spec prepare(Ecto.UUID.t()) :: {:ok, [ComparisonJob.t()]} | {:error, Error.t()}
  def prepare(snapshot_id) do
    with {:ok, context} <- context(snapshot_id),
         :ok <- validate_evidence(context) do
      {:ok,
       context.revision.definition
       |> Definition.comparisons()
       |> Enum.with_index(fn _comparison, position ->
         %ComparisonJob{comparison_position: position}
       end)}
    end
  end

  @spec evaluate(Ecto.UUID.t(), ComparisonJob.t()) ::
          {:ok, Comparison.Statistics.t()} | {:error, Error.t()}
  def evaluate(snapshot_id, %ComparisonJob{comparison_position: position})
      when is_integer(position) and position >= 0 do
    with {:ok, context} <- context(snapshot_id),
         definition = context.revision.definition,
         {:ok, comparison} <- Enum.fetch(Definition.comparisons(definition), position),
         {:ok, evidence} <- Enum.fetch(context.snapshot.evidence.comparisons, position),
         :ok <- validate_comparison(context, comparison, evidence),
         bound = bound(definition, comparison),
         {:ok, result} <- Compute.compare(input(evidence, bound), definition.analysis) do
      {:ok, statistics(result, definition.analysis.confidence_level)}
    else
      {:error, %Error{}} = error -> error
      _invalid -> invalid_input()
    end
  end

  def evaluate(_snapshot_id, _job), do: invalid_input()

  @spec correct(Ecto.UUID.t(), [Comparison.Statistics.t()]) ::
          {:ok, AnalysisContract.Output.t()} | {:error, Error.t()}
  def correct(snapshot_id, statistics) do
    with {:ok, context} <- context(snapshot_id),
         :ok <- validate_statistics(context.revision.definition, statistics) do
      {:ok, corrected(context.revision.definition, statistics)}
    end
  end

  @doc "Check the complete terminal family against its frozen method and correction policy."
  @spec validate_output(Definition.t(), AnalysisContract.Output.t()) :: :ok | {:error, Error.t()}
  def validate_output(
        definition,
        %AnalysisContract.Output{
          family_result: %CorrectedFamily{comparisons: comparisons}
        } = output
      )
      when is_list(comparisons) do
    with true <- compatible_contract?(definition),
         true <- Enum.all?(comparisons, &match?(%CorrectedFamily.Comparison{}, &1)),
         statistics = Enum.map(comparisons, & &1.statistics),
         :ok <- validate_statistics(definition, statistics),
         true <- output == corrected(definition, statistics) do
      :ok
    else
      _invalid -> invalid_input()
    end
  end

  def validate_output(_definition, _output), do: invalid_input()

  defp context(snapshot_id) do
    with {:ok, %{phase: %{phase: :final_collection}} = context} <-
           stored(Persistence.fetch_evidence_context(snapshot_id)),
         {:ok, _witness} <-
           stored(Persistence.fetch_execution_phase(context.execution.id, :final_analysis)),
         :ok <- validate_provenance(context.revision.definition),
         true <-
           match?(
             %{plan_count_per_side: plans, attacks_per_plan: attacks}
             when is_integer(plans) and plans > 0 and is_integer(attacks) and attacks > 0,
             context.execution.selection
           ),
         true <-
           length(context.snapshot.evidence.comparisons) ==
             length(Definition.comparisons(context.revision.definition)) do
      {:ok, context}
    else
      {:error, %Error{}} = error -> error
      _invalid -> invalid_input()
    end
  end

  @doc "Recheck the frozen Final contracts and measurement label before work or acceptance."
  @spec validate_provenance(Definition.t()) :: :ok | {:error, Error.t()}
  def validate_provenance(%Definition{provenance: provenance} = definition) do
    label = Application.get_env(:network_defense, :measured_environment_revision)

    if is_binary(label) and label != "" and label == provenance.environment_label and
         compatible_contract?(definition),
       do: :ok,
       else: invalid_input()
  end

  defp compatible_contract?(%Definition{provenance: provenance}) do
    provenance.method == Definition.method() and
      provenance.seed_contract == Randomness.contract()
  end

  defp validate_evidence(context) do
    definition = context.revision.definition

    definition
    |> Definition.comparisons()
    |> Enum.zip(context.snapshot.evidence.comparisons)
    |> Enum.reduce_while(:ok, fn {comparison, evidence}, :ok ->
      case validate_comparison(context, comparison, evidence) do
        :ok -> {:cont, :ok}
        failure -> {:halt, failure}
      end
    end)
  end

  defp validate_comparison(context, comparison, evidence) do
    definition = context.revision.definition
    selection = context.execution.selection
    root = Randomness.evaluation_root(definition, :final, comparison.tier)
    seeds = Enum.map(1..selection.attacks_per_plan, &Seed.child_seed(root, &1))

    if evidence.attack_seeds == seeds and
         dimensions?(evidence.alternative, selection) and
         dimensions?(evidence.reference, selection),
       do: :ok,
       else: invalid_input()
  end

  defp dimensions?(matrix, selection) when is_list(matrix) do
    length(matrix) == selection.plan_count_per_side and
      Enum.all?(matrix, &(is_list(&1) and length(&1) == selection.attacks_per_plan))
  end

  defp dimensions?(_matrix, _selection), do: false

  defp bound(definition, comparison) do
    definition.tiers
    |> Enum.find(&(&1.tier == comparison.tier))
    |> Map.fetch!(:mission_impact_bound)
  end

  defp input(evidence, bound) do
    %{
      alternative: evidence.alternative,
      reference: evidence.reference,
      lower_bound: bound.minimum,
      upper_bound: bound.maximum
    }
  end

  defp statistics(result, confidence) do
    %Comparison.Statistics{
      method: :matching_bounded_mean_v1,
      estimate: %Comparison.Estimate{
        contrast: :alternative_minus_reference,
        value: result.estimate
      },
      interval: %Comparison.Interval{
        confidence_level: confidence / 1,
        lower: result.lower,
        upper: result.upper
      },
      test: %Comparison.Test{
        method: :sign_conservative_betting,
        alternative: :two_sided,
        raw_p_value: result.p_value
      },
      assessment: %Comparison.Assessment{
        status: if(result.informative, do: :informative, else: :non_informative),
        warnings: result.warnings
      }
    }
  end

  defp validate_statistics(definition, statistics) when is_list(statistics) do
    declared = Definition.comparisons(definition)

    if length(statistics) == length(declared) and
         Enum.all?(Enum.zip(declared, statistics), fn {comparison, result} ->
           valid_statistics?(
             result,
             definition.analysis.confidence_level,
             bound(definition, comparison)
           )
         end),
       do: :ok,
       else: invalid_input()
  end

  defp validate_statistics(_definition, _statistics), do: invalid_input()

  defp valid_statistics?(
         %Comparison.Statistics{
           method: :matching_bounded_mean_v1,
           estimate: %Comparison.Estimate{contrast: :alternative_minus_reference, value: estimate},
           interval: %Comparison.Interval{
             confidence_level: confidence,
             lower: lower,
             upper: upper
           },
           test: %Comparison.Test{
             method: :sign_conservative_betting,
             alternative: :two_sided,
             raw_p_value: p
           },
           assessment: %Comparison.Assessment{} = assessment
         },
         confidence,
         bound
       ) do
    range = bound.maximum - bound.minimum

    valid_interval?(estimate, lower, upper, range) and
      probability?(p) and valid_assessment?(assessment) and
      conservative_fallback?(assessment, lower, upper, p, range)
  end

  defp valid_statistics?(_statistics, _confidence, _bound), do: false

  defp valid_interval?(estimate, lower, upper, range) do
    Enum.all?([estimate, lower, upper], &finite?/1) and
      lower >= -range and lower <= estimate and estimate <= upper and upper <= range
  end

  defp probability?(value), do: finite?(value) and value >= 0 and value <= 1

  defp valid_assessment?(%{status: :informative, warnings: []}), do: true
  defp valid_assessment?(%{status: :non_informative, warnings: [:empty_inversion]}), do: true
  defp valid_assessment?(_assessment), do: false

  defp conservative_fallback?(%{status: :informative}, _lower, _upper, _p, _range), do: true

  defp conservative_fallback?(_assessment, lower, upper, p, range),
    do: lower == -range and upper == range and p == 1

  defp finite?(value), do: is_number(value) and abs(value) <= 1.797_693_134_862_315_7e308

  defp corrected(definition, statistics) do
    corrections =
      Compute.holm(Enum.map(statistics, & &1.test.raw_p_value), definition.family.alpha)

    comparisons =
      Enum.zip_with(statistics, corrections, fn result, correction ->
        %CorrectedFamily.Comparison{
          statistics: result,
          adjustment: %Comparison.Adjustment{
            adjusted_p_value: correction.adjusted_p_value,
            reject_null: correction.reject?
          }
        }
      end)

    %AnalysisContract.Output{family_result: %CorrectedFamily{comparisons: comparisons}}
  end

  defp stored({:error, %Persistence.Error{} = error}), do: {:error, Views.error(error)}
  defp stored(result), do: result

  defp invalid_input do
    {:error,
     %Error{
       category: :unavailable,
       issues: [
         %Error.Issue{
           code: "invalid_final_analysis_input",
           path: [],
           message:
             "Final analysis requires complete accepted evidence and a valid comparison family."
         }
       ]
     }}
  end
end
