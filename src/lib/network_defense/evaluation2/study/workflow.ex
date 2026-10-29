defmodule NetworkDefense.Evaluation2.Study.Workflow do
  @moduledoc """
  Phase sequencing between the study lifecycle and Gust.

  The workflow dispatches one Gust phase run at a time, awaits its terminal task,
  and decodes the typed output. Pilot collection and Pilot analysis run
  automatically and end at the approval gate. Final collection runs one Gust run
  per declared tier, and Final analysis runs after every tier passed the replica
  equality gate.

  A failed run applies the lifecycle failure event. Task retry, mapped batches,
  and dependency fan-in stay with Gust.
  """

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation2.Contracts.PhaseContract
  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.{StudyExecution, StudyResult}

  @type dag :: module()

  @type terminal_task :: atom()

  @typedoc "Decoder of the stored terminal task result."
  @type decode_output :: (PhaseContract.params() -> PhaseContract.output())

  @type pilot_result :: {:paused, StudyExecution.t()} | {:error, StudyError.t()}

  @type final_result :: {:completed, StudyResult.t()} | {:error, StudyError.t()}

  @doc """
  Run Pilot collection, Pilot analysis, and the acceptance that opens the
  approval gate.

  A valid Pilot outcome always pauses before Final collection. The caller decides
  when Final collection starts.
  """
  @spec run_pilot(StudyExecution.t()) :: pilot_result()
  def run_pilot(_execution), do: raise(NotImplementedError, function: :run_pilot)

  @doc """
  Run Final collection, Final analysis, and result storage.

  Tiers run sequentially in the closed tier order. Every tier run is its own Gust
  run.
  """
  @spec run_final(StudyExecution.t()) :: final_result()
  def run_final(_execution), do: raise(NotImplementedError, function: :run_final)

  @doc """
  Run one Gust phase DAG and decode its terminal task result.

  The run is linked to its phase before dispatch, and a failed run maps to the
  bounded study error.
  """
  @spec run_phase(dag(), PhaseContract.params(), terminal_task(), decode_output()) ::
          {:ok, PhaseContract.output()} | {:error, StudyError.t()}
  def run_phase(_dag, _input, _terminal_task, _decode_output),
    do: raise(NotImplementedError, function: :run_phase)
end
