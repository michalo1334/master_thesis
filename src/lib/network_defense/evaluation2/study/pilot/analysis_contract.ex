defmodule NetworkDefense.Evaluation2.Study.Pilot.AnalysisContract do
  @moduledoc """
  Typed transport of one native Pilot Analysis run.

  Root input names the canonical PhaseRun and accepted Pilot snapshot.
  Workflow separately proves exact root binding and canonical succeeded
  completion. Decoding alone is not proof of phase ownership or acceptance.

  Terminal output contains the compact outcome and complete candidate summaries.
  Only the outcome lives on the execution; the detailed report remains in the
  Gust terminal result. Pilot.Analysis validates complete candidate/comparison
  membership, pass decisions and recommendation against the frozen definition.

  Explicit codecs preserve the scientific value types across Gust JSON storage.
  They do not rerun numerical inference or authenticate stored evidence.
  """

  alias NetworkDefense.Evaluation2.Study.Pilot.AnalysisContract.{Input, Output}
  alias NetworkDefense.Evaluation2.Study.Pilot.Summary
  alias NetworkDefense.Evaluation2.Study.PilotOutcome

  @typedoc "One JSON-safe Gust parameter object."
  @type params :: %{required(String.t()) => term()}

  @recommended "recommended"
  @insufficient "insufficient"

  @doc """
  Encode the root input of one Pilot analysis run as JSON-safe run parameters.
  """
  @spec to_params(Input.t()) :: params()
  def to_params(%Input{phase_run_id: phase_run_id, snapshot_id: snapshot_id}) do
    %{
      "study_phase_run_id" => phase_run_id,
      "study_evidence_snapshot_id" => snapshot_id
    }
  end

  @doc """
  Decode the stored input of one Pilot analysis run.

  Only the canonical lower-case UUID form is accepted, so a decoded input names
  exactly one stored phase run and one stored snapshot.
  """
  @spec decode_input(map()) :: {:ok, Input.t()} | :error
  def decode_input(%{
        "study_phase_run_id" => phase_run_id,
        "study_evidence_snapshot_id" => snapshot_id
      }) do
    with {:ok, phase_run_id} <- canonical_uuid(phase_run_id),
         {:ok, snapshot_id} <- canonical_uuid(snapshot_id) do
      {:ok, %Input{phase_run_id: phase_run_id, snapshot_id: snapshot_id}}
    end
  end

  def decode_input(_params), do: :error

  @doc """
  Encode the terminal output of one Pilot analysis run as a JSON-safe result.

  The caller that stores the run result owns this step, so the terminal task and
  the run completion keep one stored shape.
  """
  @spec encode_output(Output.t()) :: {:ok, params()} | :error
  def encode_output(%Output{outcome: outcome, candidates: candidates})
      when is_list(candidates) do
    with {:ok, outcome} <- encode_outcome(outcome),
         {:ok, candidates} <- traverse(candidates, &encode_candidate/1) do
      {:ok, %{"outcome" => outcome, "candidates" => candidates}}
    end
  end

  def encode_output(_output), do: :error

  @doc """
  Decode the stored terminal result of one Pilot analysis run.

  The complete candidate list stays in this value, because the supported Pilot
  report reads it back from the completed run.
  """
  @spec decode_output(map()) :: {:ok, Output.t()} | :error
  def decode_output(%{"outcome" => outcome, "candidates" => candidates})
      when is_list(candidates) do
    with {:ok, outcome} <- decode_outcome(outcome),
         {:ok, candidates} <- traverse(candidates, &decode_candidate/1) do
      {:ok, %Output{outcome: outcome, candidates: candidates}}
    end
  end

  def decode_output(_params), do: :error

  @doc false
  @spec decode_output!(map()) :: Output.t()
  def decode_output!(params) do
    {:ok, output} = decode_output(params)
    output
  end

  # --- decision ----------------------------------------------------------

  defp encode_outcome(%PilotOutcome{
         outcome: :recommended,
         candidate_id: candidate_id,
         plan_count_per_side: plan_count_per_side,
         attacks_per_plan: attacks_per_plan
       })
       when is_binary(candidate_id) and is_integer(plan_count_per_side) and
              plan_count_per_side > 0 and is_integer(attacks_per_plan) and attacks_per_plan > 0 do
    {:ok,
     %{
       "outcome" => @recommended,
       "candidate_id" => candidate_id,
       "plan_count_per_side" => plan_count_per_side,
       "attacks_per_plan" => attacks_per_plan
     }}
  end

  defp encode_outcome(%PilotOutcome{
         outcome: :insufficient,
         candidate_id: nil,
         plan_count_per_side: nil,
         attacks_per_plan: nil
       }) do
    {:ok,
     %{
       "outcome" => @insufficient,
       "candidate_id" => nil,
       "plan_count_per_side" => nil,
       "attacks_per_plan" => nil
     }}
  end

  defp encode_outcome(_outcome), do: :error

  defp decode_outcome(%{
         "outcome" => @recommended,
         "candidate_id" => candidate_id,
         "plan_count_per_side" => plan_count_per_side,
         "attacks_per_plan" => attacks_per_plan
       })
       when is_binary(candidate_id) and is_integer(plan_count_per_side) and
              plan_count_per_side > 0 and is_integer(attacks_per_plan) and attacks_per_plan > 0 do
    {:ok,
     %PilotOutcome{
       outcome: :recommended,
       candidate_id: candidate_id,
       plan_count_per_side: plan_count_per_side,
       attacks_per_plan: attacks_per_plan
     }}
  end

  defp decode_outcome(%{
         "outcome" => @insufficient,
         "candidate_id" => nil,
         "plan_count_per_side" => nil,
         "attacks_per_plan" => nil
       }) do
    {:ok, %PilotOutcome{outcome: :insufficient}}
  end

  defp decode_outcome(_outcome), do: :error

  # --- candidate summaries -----------------------------------------------

  defp encode_candidate(%Summary{
         candidate_position: candidate_position,
         candidate_id: candidate_id,
         plan_count_per_side: plan_count_per_side,
         attacks_per_plan: attacks_per_plan,
         predicted_runtime_ms: predicted_runtime_ms,
         comparisons: comparisons
       })
       when is_integer(candidate_position) and candidate_position >= 0 and
              is_binary(candidate_id) and is_integer(plan_count_per_side) and
              plan_count_per_side > 0 and is_integer(attacks_per_plan) and attacks_per_plan > 0 and
              is_number(predicted_runtime_ms) and is_list(comparisons) do
    with {:ok, comparisons} <- traverse(comparisons, &encode_comparison/1) do
      {:ok,
       %{
         "candidate_position" => candidate_position,
         "candidate_id" => candidate_id,
         "plan_count_per_side" => plan_count_per_side,
         "attacks_per_plan" => attacks_per_plan,
         "predicted_runtime_ms" => predicted_runtime_ms,
         "comparisons" => comparisons
       }}
    end
  end

  defp encode_candidate(_summary), do: :error

  defp decode_candidate(%{
         "candidate_position" => candidate_position,
         "candidate_id" => candidate_id,
         "plan_count_per_side" => plan_count_per_side,
         "attacks_per_plan" => attacks_per_plan,
         "predicted_runtime_ms" => predicted_runtime_ms,
         "comparisons" => comparisons
       })
       when is_integer(candidate_position) and candidate_position >= 0 and
              is_binary(candidate_id) and is_integer(plan_count_per_side) and
              plan_count_per_side > 0 and is_integer(attacks_per_plan) and attacks_per_plan > 0 and
              is_number(predicted_runtime_ms) and is_list(comparisons) do
    with {:ok, comparisons} <- traverse(comparisons, &decode_comparison/1) do
      {:ok,
       %Summary{
         candidate_position: candidate_position,
         candidate_id: candidate_id,
         plan_count_per_side: plan_count_per_side,
         attacks_per_plan: attacks_per_plan,
         predicted_runtime_ms: predicted_runtime_ms,
         comparisons: comparisons
       }}
    end
  end

  defp decode_candidate(_summary), do: :error

  defp encode_comparison(%Summary.Comparison{
         comparison_position: comparison_position,
         guarded_half_width: guarded_half_width,
         informative: informative,
         passes: passes
       })
       when is_integer(comparison_position) and comparison_position >= 0 and
              is_number(guarded_half_width) and is_boolean(informative) and is_boolean(passes) do
    {:ok,
     %{
       "comparison_position" => comparison_position,
       "guarded_half_width" => guarded_half_width,
       "informative" => informative,
       "passes" => passes
     }}
  end

  defp encode_comparison(_comparison), do: :error

  # A JSON number keeps integral values as integers, so the decoded half-width is
  # normalized to the declared float type.
  defp decode_comparison(%{
         "comparison_position" => comparison_position,
         "guarded_half_width" => guarded_half_width,
         "informative" => informative,
         "passes" => passes
       })
       when is_integer(comparison_position) and comparison_position >= 0 and
              is_number(guarded_half_width) and is_boolean(informative) and is_boolean(passes) do
    {:ok,
     %Summary.Comparison{
       comparison_position: comparison_position,
       guarded_half_width: guarded_half_width * 1.0,
       informative: informative,
       passes: passes
     }}
  end

  defp decode_comparison(_comparison), do: :error

  # --- shared helpers ----------------------------------------------------

  # One unusable entry rejects the whole stored value, so a partial candidate
  # list never reaches selection or reporting.
  @spec traverse([term()], (term() -> {:ok, value} | :error)) :: {:ok, [value]} | :error
        when value: var
  defp traverse(entries, codec) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, decoded} ->
      case codec.(entry) do
        {:ok, value} -> {:cont, {:ok, [value | decoded]}}
        :error -> {:halt, :error}
      end
    end)
    |> completed()
  end

  defp completed({:ok, decoded}), do: {:ok, Enum.reverse(decoded)}
  defp completed(:error), do: :error

  @spec canonical_uuid(term()) :: {:ok, Ecto.UUID.t()} | :error
  defp canonical_uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, ^value} -> {:ok, value}
      _not_canonical -> :error
    end
  end

  defp canonical_uuid(_value), do: :error
end
