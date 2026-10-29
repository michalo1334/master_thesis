defmodule NetworkDefense.Evaluation2.Study.Phases do
  @moduledoc false

  # Phase and phase-run records of one execution.
  #
  # A phase groups the Gust runs of one declared phase. Every Gust run has one
  # phase-run record: the `:single` key covers Pilot collection, Pilot analysis,
  # and Final analysis, and one tier key covers each Final tier.
  #
  # Run status, task status, and task errors stay in Gust. Acceptance writes no
  # run status here.

  alias NetworkDefense.Evaluation2.NotImplementedError
  alias NetworkDefense.Evaluation2.Placeholder
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.StudyExecution
  alias NetworkDefense.Evaluation2.StudyPhase
  alias NetworkDefense.Evaluation2.StudyPhaseRun

  # Create or load the phase record of one execution.
  @spec create_or_load(StudyExecution.t(), StudyPhase.phase_kind()) ::
          {:ok, StudyPhase.t()} | {:error, Error.t()}
  def create_or_load(_execution, _phase_kind),
    do: {:error, Placeholder.error(:create_or_load)}

  @spec fetch!(Ecto.UUID.t(), StudyPhase.phase_kind()) :: StudyPhase.t()
  def fetch!(_execution_id, _phase_kind), do: raise(NotImplementedError, function: :fetch!)

  # Create or load one Gust run link of a phase.
  @spec create_or_load_run(StudyPhase.t(), StudyPhaseRun.run_key()) ::
          {:ok, StudyPhaseRun.t()} | {:error, Error.t()}
  def create_or_load_run(_phase, _run_key),
    do: {:error, Placeholder.error(:create_or_load_run)}

  @spec run!(Ecto.UUID.t()) :: StudyPhaseRun.t()
  def run!(_phase_run_id), do: raise(NotImplementedError, function: :run!)

  @spec runs(StudyPhase.t()) :: [StudyPhaseRun.t()]
  def runs(_phase), do: raise(NotImplementedError, function: :runs)
end
