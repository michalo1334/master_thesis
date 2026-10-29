defmodule NetworkDefense.Evaluation2.Study.Workflow do
  @moduledoc false

  alias NetworkDefense.Evaluation2.Contracts.{
    FinalAnalysisContract,
    FinalTierContract,
    PilotAnalysisContract,
    PilotCollectionContract
  }

  # Typed wrappers bind each phase to its decoder. Shared Gust mechanics stay private.
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.StudyExecution
  alias NetworkDefense.Evaluation2.StudyResult

  @type pilot_result :: {:paused, StudyExecution.t()} | {:error, Error.t()}
  @type final_result :: {:completed, StudyResult.t()} | {:error, Error.t()}

  @spec run_pilot(StudyExecution.t()) :: pilot_result()
  def run_pilot(_execution), do: raise(NotImplementedError, function: :run_pilot)

  @spec run_final(StudyExecution.t()) :: final_result()
  def run_final(_execution), do: raise(NotImplementedError, function: :run_final)

  @spec run_pilot_collection(PilotCollectionContract.Input.t()) ::
          {:ok, PilotCollectionContract.Output.t()} | {:error, Error.t()}
  def run_pilot_collection(input) do
    dispatch(PilotCollectionContract, input, :pilot_collection_terminal)
    |> decode_result(&PilotCollectionContract.decode_output!/1)
  end

  @spec run_pilot_analysis(PilotAnalysisContract.Input.t()) ::
          {:ok, PilotAnalysisContract.Output.t()} | {:error, Error.t()}
  def run_pilot_analysis(input) do
    dispatch(PilotAnalysisContract, input, :pilot_analysis_terminal)
    |> decode_result(&PilotAnalysisContract.decode_output!/1)
  end

  @spec run_final_tier(FinalTierContract.Input.t()) ::
          {:ok, FinalTierContract.Output.t()} | {:error, Error.t()}
  def run_final_tier(input) do
    dispatch(FinalTierContract, input, :final_tier_terminal)
    |> decode_result(&FinalTierContract.decode_output!/1)
  end

  @spec run_final_analysis(FinalAnalysisContract.Input.t()) ::
          {:ok, FinalAnalysisContract.Output.t()} | {:error, Error.t()}
  def run_final_analysis(input) do
    dispatch(FinalAnalysisContract, input, :final_analysis_terminal)
    |> decode_result(&FinalAnalysisContract.decode_output!/1)
  end

  # Future Gust dispatch will encode the phase input and read its terminal result.
  @spec dispatch(module(), map(), atom()) :: {:ok, map()} | {:error, Error.t()}
  defp dispatch(_contract, _params, _terminal), do: {:error, Placeholder.error(:dispatch)}

  # The scaffold dispatcher returns only errors until Gust execution is implemented.
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
