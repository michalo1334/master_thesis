defmodule NetworkDefense.Evaluation.Study.FinalBindingContext do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}
  alias NetworkDefense.Evaluation.Study.{FinalSelection, PilotOutcome, Revisions}
  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  @usable_final_states [:collecting_final, :analyzing_final, :succeeded]

  @enforce_keys [:execution, :selection, :definition, :pilot_outcome, :accepted_pilot_phase]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          execution: StudyExecution.t(),
          selection: FinalSelection.t(),
          definition: Definition.t(),
          pilot_outcome: PilotOutcome.t(),
          accepted_pilot_phase: StudyPhase.t()
        }

  @spec load(Ecto.UUID.t()) :: {:ok, t()} | {:error, StudyError.t()}
  def load(execution_id) do
    with {:ok, execution} <- load_execution(execution_id),
         :ok <- require_usable_final_state(execution),
         {:ok, selection} <- FinalSelection.from_execution(execution),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         {:ok, outcome} <- parse_pilot_outcome(execution.pilot_outcome),
         {:ok, phase} <- load_pilot_phase(execution),
         :ok <- verify_stored_source(execution, selection, definition, outcome, phase) do
      {:ok,
       %__MODULE__{
         execution: execution,
         selection: selection,
         definition: definition,
         pilot_outcome: outcome,
         accepted_pilot_phase: phase
       }}
    end
  end

  defp load_execution(execution_id) do
    with {:ok, id} <- Ecto.UUID.cast(execution_id),
         %StudyExecution{} = execution <- Repo.get(StudyExecution, id) do
      {:ok, execution}
    else
      _invalid_or_missing -> {:error, StudyError.study_execution_not_found()}
    end
  end

  defp require_usable_final_state(%StudyExecution{state: state})
       when state in @usable_final_states,
       do: :ok

  defp require_usable_final_state(%StudyExecution{}),
    do: {:error, StudyError.final_binding_not_allowed()}

  defp parse_pilot_outcome(params) do
    case PilotOutcome.parse(params) do
      {:ok, %PilotOutcome{} = outcome} -> {:ok, outcome}
      {:error, %StudyError{}} -> {:error, StudyError.pilot_source_incomplete()}
    end
  end

  defp load_pilot_phase(%StudyExecution{} = execution) do
    case Repo.one(
           from phase in StudyPhase,
             where: phase.execution_id == ^execution.id and phase.phase == :pilot_analysis
         ) do
      %StudyPhase{} = phase -> {:ok, phase}
      nil -> {:error, StudyError.pilot_source_incomplete()}
    end
  end

  defp verify_stored_source(execution, selection, definition, outcome, phase) do
    with :ok <- verify_stored_phase(execution, phase),
         :ok <- verify_declared_candidate(selection, definition) do
      verify_outcome(selection, outcome)
    end
  end

  defp verify_stored_phase(%StudyExecution{} = execution, %StudyPhase{} = phase) do
    if is_integer(phase.gust_run_id) and phase.gust_run_id > 0 and
         phase.result_ref == execution.pilot_outcome and is_nil(phase.error) do
      :ok
    else
      {:error, StudyError.pilot_source_incomplete()}
    end
  end

  defp verify_declared_candidate(%FinalSelection{} = selection, %Definition{} = definition) do
    case Enum.find(definition.pilot.candidates, &(&1.id == selection.candidate_id)) do
      %{plan_count_per_side: plan_count, attacks_per_plan: attacks}
      when plan_count == selection.plan_count_per_side and
             attacks == selection.attacks_per_plan ->
        :ok

      _missing_or_changed ->
        {:error, StudyError.pilot_source_incomplete()}
    end
  end

  defp verify_outcome(
         %FinalSelection{pilot_override: false} = selection,
         %PilotOutcome{outcome: :recommended} = outcome
       ) do
    if outcome.candidate_id == selection.candidate_id and
         outcome.plan_count_per_side == selection.plan_count_per_side and
         outcome.attacks_per_plan == selection.attacks_per_plan do
      :ok
    else
      {:error, StudyError.pilot_source_incomplete()}
    end
  end

  defp verify_outcome(
         %FinalSelection{pilot_override: true},
         %PilotOutcome{outcome: :insufficient}
       ),
       do: :ok

  defp verify_outcome(_selection, _outcome),
    do: {:error, StudyError.pilot_source_incomplete()}
end
