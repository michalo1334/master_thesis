defmodule NetworkDefense.Evaluation.Study.FinalBindingContext do
  @moduledoc false

  import Ecto.Query

  alias NetworkDefense.Evaluation.Study.Contracts.{Definition, StudyError}

  alias NetworkDefense.Evaluation.Study.{
    Collection,
    ExecutionAccess,
    FinalSelection,
    PhaseRuns,
    PilotOutcome,
    Revisions
  }

  alias NetworkDefense.Evaluation.{StudyExecution, StudyPhase}
  alias NetworkDefense.Repo

  @usable_final_states [:collecting_final, :analyzing_final, :succeeded]

  @enforce_keys [:execution, :selection, :definition, :pilot_outcome, :accepted_pilot_phase]
  defstruct @enforce_keys ++ [accepted_final_collection_phase: nil]

  @type t :: %__MODULE__{
          execution: StudyExecution.t(),
          selection: FinalSelection.t(),
          definition: Definition.t(),
          pilot_outcome: PilotOutcome.t(),
          accepted_pilot_phase: StudyPhase.t(),
          accepted_final_collection_phase: StudyPhase.t() | nil
        }

  @spec load(Ecto.UUID.t()) :: {:ok, t()} | {:error, StudyError.t()}
  def load(execution_id) do
    with {:ok, execution} <- ExecutionAccess.fetch(execution_id),
         :ok <- require_usable_final_state(execution),
         {:ok, selection} <- FinalSelection.from_execution(execution),
         {:ok, definition} <- Revisions.load_definition(execution.study_revision_id),
         {:ok, outcome} <- PilotOutcome.parse_accepted_source(execution.pilot_outcome),
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

  @spec load_for_analysis(Ecto.UUID.t()) :: {:ok, t()} | {:error, StudyError.t()}
  def load_for_analysis(execution_id) do
    with {:ok, context} <- load(execution_id),
         :ok <- require_post_collection_state(context.execution),
         {:ok, phase} <- load_final_collection_phase(context.execution),
         :ok <- verify_final_collection_phase(phase, context.definition) do
      {:ok, %{context | accepted_final_collection_phase: phase}}
    end
  end

  defp require_usable_final_state(%StudyExecution{state: state})
       when state in @usable_final_states,
       do: :ok

  defp require_usable_final_state(%StudyExecution{}),
    do: {:error, StudyError.final_binding_not_allowed()}

  defp load_pilot_phase(%StudyExecution{} = execution) do
    case Repo.one(
           from phase in StudyPhase,
             where: phase.execution_id == ^execution.id and phase.phase == :pilot_analysis
         ) do
      %StudyPhase{} = phase -> {:ok, phase}
      nil -> {:error, StudyError.pilot_source_incomplete()}
    end
  end

  defp require_post_collection_state(%StudyExecution{state: state})
       when state in [:analyzing_final, :succeeded],
       do: :ok

  defp require_post_collection_state(%StudyExecution{}),
    do: {:error, StudyError.final_source_mismatch()}

  defp load_final_collection_phase(%StudyExecution{} = execution) do
    case Repo.one(
           from phase in StudyPhase,
             where: phase.execution_id == ^execution.id and phase.phase == :final_collection
         ) do
      %StudyPhase{} = phase -> {:ok, phase}
      nil -> {:error, StudyError.final_source_mismatch()}
    end
  end

  # The accepted Final collection phase holds one linked Gust run for each
  # declared tier in first-seen comparison order, one accepted snapshot, and no
  # scalar phase run.
  defp verify_final_collection_phase(%StudyPhase{} = phase, %Definition{} = definition) do
    with true <- is_nil(phase.gust_run_id),
         true <- is_nil(phase.error),
         {:ok, _snapshot_id} <- Ecto.UUID.cast(phase.snapshot_id),
         :ok <- verify_ordered_family(phase, definition) do
      :ok
    else
      _invalid_or_incomplete -> {:error, StudyError.final_source_mismatch()}
    end
  end

  defp verify_ordered_family(%StudyPhase{id: phase_id}, %Definition{} = definition) do
    with {:ok, tiers} <- Collection.tier_order(definition),
         {:ok, rows} <- PhaseRuns.ordered_for_phase(phase_id),
         true <- Enum.map(rows, & &1.tier) == tiers,
         true <- Enum.map(rows, & &1.tier_position) == tier_positions(tiers),
         true <- Enum.all?(rows, &(&1.study_phase_id == phase_id)),
         true <- Enum.all?(rows, &(is_integer(&1.gust_run_id) and &1.gust_run_id > 0)) do
      :ok
    else
      _incomplete -> {:error, StudyError.final_source_mismatch()}
    end
  end

  defp tier_positions(tiers), do: Enum.to_list(0..(length(tiers) - 1))

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
