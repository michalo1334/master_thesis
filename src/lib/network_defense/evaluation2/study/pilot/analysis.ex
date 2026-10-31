defmodule NetworkDefense.Evaluation2.Study.Pilot.Analysis do
  @moduledoc """
  Prepares Pilot comparison jobs from a collection snapshot and its definition.

  Candidates share each comparison's deterministic planning stream. Evaluation and
  outcome selection remain unavailable.
  """

  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.{Definition, Randomness}
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Error.Issue
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Pilot.AnalysisContract
  alias NetworkDefense.Evaluation2.Study.Pilot.Assessment
  alias NetworkDefense.Evaluation2.Study.Pilot.Job
  alias NetworkDefense.Evaluation2.Study.PilotResult
  alias NetworkDefense.Evaluation2.Study.Views

  @doc """
  Prepare jobs in candidate order and then comparison order.

  Logical comparison identity determines the stream. Candidate sizes share it.
  """
  @spec prepare(Ecto.UUID.t()) :: {:ok, [Job.t()]} | {:error, Error.t()}
  def prepare(snapshot_id) do
    case Persistence.fetch_evidence_context(snapshot_id) do
      {:ok, context} -> prepare_jobs(context)
      {:error, error} -> {:error, Views.error(error)}
    end
  end

  defp prepare_jobs(%{
         phase: %{phase: :pilot_collection},
         revision: %{definition: %Definition{} = definition},
         snapshot: %{evidence: %{comparisons: evidence}}
       })
       when is_list(evidence) do
    comparisons = Definition.comparisons(definition)

    if length(comparisons) == length(evidence) do
      {:ok,
       for {_candidate, candidate_position} <- Enum.with_index(definition.pilot.candidates),
           {comparison, comparison_position} <- Enum.with_index(comparisons) do
         %Job{
           candidate_position: candidate_position,
           comparison_position: comparison_position,
           stream_seed: Randomness.pilot_planning_seed(definition, comparison)
         }
       end}
    else
      invalid_input()
    end
  end

  defp prepare_jobs(_context), do: invalid_input()

  defp invalid_input do
    {:error,
     %Error{
       category: :unavailable,
       issues: [
         %Issue{
           code: "invalid_pilot_analysis_input",
           path: [],
           message: "Pilot analysis input is invalid."
         }
       ]
     }}
  end

  # Assess one candidate and comparison pair against the accepted snapshot.
  #
  # The assessment passes when every outer subsample is informative and the
  # guarded half-width stays within the declared target.
  @spec evaluate(Ecto.UUID.t(), Job.t()) ::
          {:ok, Assessment.t()} | {:error, Error.t()}
  def evaluate(_snapshot_id, _job), do: {:error, Placeholder.error(:evaluate)}

  # Aggregate the assessments and select the Pilot outcome.
  #
  # The selector returns the passing candidate with the smallest predicted Final
  # runtime, or `:insufficient` when no candidate passes every declared
  # comparison.
  @spec decide(Ecto.UUID.t(), [Assessment.t()]) ::
          {:ok, AnalysisContract.Output.t()} | {:error, Error.t()}
  def decide(_snapshot_id, _assessments), do: {:error, Placeholder.error(:decide)}

  @spec report(Ecto.UUID.t()) :: {:ok, PilotResult.t()} | {:error, Error.t()}
  def report(_execution_id), do: {:error, Placeholder.error(:report)}
end
