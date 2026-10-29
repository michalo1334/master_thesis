defmodule NetworkDefense.Evaluation2.Study.Workflow do
  @moduledoc false

  # Gust dispatch of the four study phases.
  #
  # Each typed wrapper binds one phase to its own contract, so a decoder mismatch
  # is a compile-time type error instead of a runtime surprise. Shared Gust
  # mechanics stay in the private dispatcher: it encodes the phase input, starts
  # or resumes the phase run, and returns the raw terminal result.
  #
  # Gust owns batch execution, dependency fan-in, and task retry. This module owns
  # no scheduler and no retry policy.

  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.{Error, Final, Persistence, Pilot}

  @type pilot_result :: {:paused, Persistence.Execution.t()} | {:error, Error.t()}
  @type final_result :: {:completed, Persistence.Result.t()} | {:error, Error.t()}

  @spec run_pilot(Persistence.Execution.t()) :: pilot_result()
  def run_pilot(_execution), do: raise(NotImplementedError, function: :run_pilot)

  @spec run_final(Persistence.Execution.t()) :: final_result()
  def run_final(_execution), do: raise(NotImplementedError, function: :run_final)

  @spec run_pilot_collection(Pilot.CollectionContract.Input.t()) ::
          {:ok, Pilot.CollectionContract.Output.t()} | {:error, Error.t()}
  def run_pilot_collection(input) do
    dispatch(Pilot.CollectionContract, input, :assemble_pilot_snapshot)
    |> decode_result(&Pilot.CollectionContract.decode_output!/1)
  end

  @spec run_pilot_analysis(Pilot.AnalysisContract.Input.t()) ::
          {:ok, Pilot.AnalysisContract.Output.t()} | {:error, Error.t()}
  def run_pilot_analysis(input) do
    dispatch(Pilot.AnalysisContract, input, :select_pilot_outcome)
    |> decode_result(&Pilot.AnalysisContract.decode_output!/1)
  end

  @spec run_final_tier(Final.TierContract.Input.t()) ::
          {:ok, Final.TierContract.Output.t()} | {:error, Error.t()}
  def run_final_tier(input) do
    dispatch(Final.TierContract, input, :complete_final_tier)
    |> decode_result(&Final.TierContract.decode_output!/1)
  end

  @spec run_final_analysis(Final.AnalysisContract.Input.t()) ::
          {:ok, Final.AnalysisContract.Output.t()} | {:error, Error.t()}
  def run_final_analysis(input) do
    dispatch(Final.AnalysisContract, input, :correct_final_family)
    |> decode_result(&Final.AnalysisContract.decode_output!/1)
  end

  # Encode the phase input, run the phase, and return its raw terminal result.
  #
  # Encoding belongs here, so a wrapper never needs a wire key of its own.
  @spec dispatch(module(), map(), atom()) :: {:ok, map()} | {:error, Error.t()}
  defp dispatch(_contract, _input, _terminal), do: {:error, Placeholder.error(:dispatch)}

  # The scaffold dispatcher returns only errors until Gust execution is
  # implemented, so the success branch stays unreachable until then.
  @dialyzer {:nowarn_function, decode_result: 2}
  @spec decode_result({:ok, map()} | {:error, Error.t()}, (map() -> result)) ::
          {:ok, result} | {:error, Error.t()}
        when result: var
  defp decode_result(result, decoder) do
    case result do
      {:ok, raw} -> {:ok, decoder.(raw)}
      {:error, error} -> {:error, error}
    end
  end
end
