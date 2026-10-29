defmodule NetworkDefense.Evaluation2.Study.Pilot.Analysis do
  @moduledoc false

  # Candidate assessment and decision of the Pilot phase.
  #
  # The three operations match the three Pilot analysis Gust stages:
  #
  #   * `prepare/1` builds one job per declared candidate and comparison pair;
  #   * `evaluate/2` assesses one pair against the accepted Pilot matrices;
  #   * `decide/2` creates the complete candidate summaries and selects the
  #     outcome.
  #
  # The accepted snapshot is the study context: it leads to the immutable
  # definition, the declared family, and the runtime evidence of the runtime
  # prediction.
  #
  # `report/1` maps the accepted terminal Gust result to the supported Pilot
  # report. Approval uses the report, including an insufficient outcome.
  #
  # This module is a phase implementation detail. It is not part of the supported
  # study API.

  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Pilot.AnalysisContract
  alias NetworkDefense.Evaluation2.Study.Pilot.Assessment
  alias NetworkDefense.Evaluation2.Study.Pilot.Job
  alias NetworkDefense.Evaluation2.Study.PilotResult

  @spec prepare(Ecto.UUID.t()) :: {:ok, [Job.t()]} | {:error, Error.t()}
  def prepare(_snapshot_id), do: {:error, Placeholder.error(:prepare)}

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
