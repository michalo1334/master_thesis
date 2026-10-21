defmodule NetworkDefense.Evaluation.Final.Source do
  @moduledoc false

  alias NetworkDefense.Evaluation.Final.Contracts.FinalError
  alias NetworkDefense.Evaluation.Pilot.Contracts.{PilotError, PilotResult}

  # Source-Pilot binding for Final analysis.
  #
  # The source must be readable through the existing public Pilot getter and
  # must be an actual recommended result. A missing, failed, still running, or
  # insufficient Pilot cannot supply a fallback count.

  @spec require_recommended_pilot(integer()) ::
          {:ok, PilotResult.t()} | {:error, FinalError.t()}
  def require_recommended_pilot(run_id) when is_integer(run_id) do
    case NetworkDefense.Evaluations.get_pilot_result(run_id) do
      {:ok, %PilotResult{} = pilot} ->
        {:ok, pilot}

      {:error, %PilotError{} = error} ->
        {:error,
         FinalError.pilot_source_invalid(
           error.code,
           "The source Pilot result is not readable."
         )}

      {:error, :not_found} ->
        {:error, FinalError.pilot_not_found()}

      {:error, :not_ready} ->
        {:error,
         FinalError.pilot_source_invalid(
           "not_ready",
           "The source Pilot run has not succeeded."
         )}

      _other ->
        {:error,
         FinalError.pilot_source_invalid(
           "unknown",
           "The source Pilot result is not readable."
         )}
    end
  end

  def require_recommended_pilot(_run_id), do: {:error, FinalError.pilot_not_found()}
end
