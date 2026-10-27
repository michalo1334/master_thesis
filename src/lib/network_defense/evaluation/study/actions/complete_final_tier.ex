defmodule NetworkDefense.Evaluation.Study.Actions.CompleteFinalTier do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.TaskFailure
  alias NetworkDefense.Evaluation.StudyPhase
  alias NetworkDefense.Evaluation.StudyPhaseRun
  alias NetworkDefense.Repo

  @impl true
  def execute(_args, %{run_id: run_id}) do
    with %{params: params} <- Gust.Flows.get_run!(run_id),
         {:ok, phase_run_id} <- uuid(params["study_phase_run_id"]),
         {:ok, phase_id} <- uuid(params["study_phase_id"]),
         {:ok, execution_id} <- uuid(params["execution_id"]),
         {:ok, tier} <- tier(params["tier"]),
         {:ok, tier_position} <- tier_position(params["tier_position"]),
         %StudyPhaseRun{tier: ^tier, tier_position: ^tier_position, study_phase_id: ^phase_id} <-
           Repo.get(StudyPhaseRun, phase_run_id),
         %StudyPhase{phase: :final_collection, execution_id: ^execution_id} <-
           Repo.get(StudyPhase, phase_id) do
      %{
        "study_phase_run_id" => phase_run_id,
        "tier" => tier,
        "tier_position" => tier_position
      }
    else
      _invalid -> TaskFailure.raise_permanent(StudyError.final_timing_invalid())
    end
  rescue
    _exception -> TaskFailure.raise_permanent(StudyError.final_timing_invalid())
  end

  defp uuid(value), do: Ecto.UUID.cast(value)

  defp tier(value) when is_binary(value) and byte_size(value) > 0, do: {:ok, value}
  defp tier(_value), do: :error

  defp tier_position(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp tier_position(_value), do: :error
end
