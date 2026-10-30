defmodule NetworkDefense.Evaluation2.Study.Persistence.Executions do
  @moduledoc false

  # Lifecycle commands of one study execution.
  #
  # A command that changes a stored execution locks its row and applies one
  # transition, and a transition into an active state creates the successor phase
  # in the same transaction. An equal repeated value returns the current state, a
  # different value conflicts. Succeeded stays succeeded, and failed or cancelled
  # executions reject late acceptance.
  #
  # Final analysis inserts the result and applies the success transition together,
  # so a successful execution always owns its result.

  import Ecto.Query

  alias Ecto.Changeset
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Definition.Candidate
  alias NetworkDefense.Evaluation2.Study.Error, as: StudyError
  alias NetworkDefense.Evaluation2.Study.Final.CorrectedFamily
  alias NetworkDefense.Evaluation2.Study.Lifecycle
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.Execution
  alias NetworkDefense.Evaluation2.Study.Persistence.Phase
  alias NetworkDefense.Evaluation2.Study.Persistence.Result
  alias NetworkDefense.Evaluation2.Study.PilotOutcome
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Repo

  # --- execution start ----------------------------------------------------

  # The transaction inserts the execution and its Pilot collection phase, so the
  # returned context never reports an active state without its phase.
  @spec start_execution(Persistence.revision_ref()) ::
          Persistence.response(Persistence.lifecycle_context())
  def start_execution(revision_ref) do
    with {:ok, identity} <- Persistence.cast_identity(revision_ref, :start_execution) do
      Persistence.tx(:start_execution, :execution, fn ->
        started_execution(identity, :start_execution)
      end)
    end
  end

  defp started_execution(identity, operation) do
    with {:ok, revision} <- Persistence.stored_revision(identity, operation),
         {:ok, execution} <- insert_execution(revision.id, operation),
         {:ok, phase} <- enter_phase(execution, operation) do
      {:ok, %{execution: execution, revision: revision, active_phase: phase}}
    end
  end

  # --- collection acceptance ----------------------------------------------

  @spec accept_pilot_collection(Ecto.UUID.t()) ::
          Persistence.response(Persistence.lifecycle_context())
  def accept_pilot_collection(phase_id) do
    accept_collection(phase_id, :accept_pilot_collection, :pilot_collection)
  end

  @spec accept_final_collection(Ecto.UUID.t()) ::
          Persistence.response(Persistence.lifecycle_context())
  def accept_final_collection(phase_id) do
    accept_collection(phase_id, :accept_final_collection, :final_collection)
  end

  defp accept_collection(phase_id, operation, kind) do
    with {:ok, uuid} <- Persistence.cast_id(phase_id, operation, :phase) do
      Persistence.tx(operation, :phase, fn -> accepted_collection(uuid, kind, operation) end)
    end
  end

  defp accepted_collection(phase_id, kind, operation) do
    with {:ok, phase} <- Persistence.stored_phase(phase_id, operation),
         :ok <- expect_phase(phase, kind, operation),
         {:ok, execution} <- lock_execution(phase.study_execution_id, operation) do
      settle_collection(execution, phase, kind, operation)
    end
  end

  # The phase kind fixes the expected state, the successor phase, and the
  # lifecycle event of one collection acceptance.
  defp collection_step(:pilot_collection),
    do: {:collecting_pilot, :pilot_analysis, :pilot_collected}

  defp collection_step(:final_collection),
    do: {:collecting_final, :final_analysis, :final_collected}

  # Accept one completed collection phase.
  #
  # The successor phase is the durable witness of a committed acceptance (Q95).
  # The phase-owned snapshot stays the required scientific artifact (Q96), so the
  # acceptance transition requires it, and every accepted retry requires both.
  defp settle_collection(execution, phase, kind, operation) do
    {expected_state, successor, event} = collection_step(kind)

    case classify(execution.state, expected_state) do
      :expected ->
        with :ok <- require_snapshot(phase.id, operation) do
          advance(execution, event, %{}, operation)
        end

      :early ->
        {:error, Persistence.error(:conflict, operation, :phase, :early_acceptance)}

      :later ->
        with :ok <- require_witness(execution, successor, operation),
             :ok <- require_snapshot(phase.id, operation) do
          current(execution, operation)
        end

      :aborted ->
        settle_aborted_collection(execution, phase, successor, operation)
    end
  end

  # An aborted execution keeps its status. Its successor phase states whether the
  # acceptance committed before the abort, and a committed acceptance keeps its
  # snapshot.
  defp settle_aborted_collection(execution, phase, successor, operation) do
    if Persistence.phase_present?(execution.id, successor) do
      with :ok <- require_snapshot(phase.id, operation) do
        current(execution, operation)
      end
    else
      {:error, Persistence.error(:conflict, operation, :phase, :late_completion)}
    end
  end

  # A prepared snapshot proves preparation only, so it cannot prove acceptance.
  defp require_snapshot(phase_id, operation) do
    if Persistence.snapshot_present?(phase_id) do
      :ok
    else
      {:error, Persistence.error(:storage, operation, :evidence_snapshot, :not_prepared)}
    end
  end

  defp require_witness(%Execution{id: id}, successor, operation) do
    if Persistence.phase_present?(id, successor) do
      :ok
    else
      {:error, Persistence.error(:storage, operation, :phase, :missing_successor_phase)}
    end
  end

  # --- analysis acceptance ------------------------------------------------

  @spec accept_pilot_analysis(Ecto.UUID.t(), PilotOutcome.t()) ::
          Persistence.response(Persistence.lifecycle_context())
  def accept_pilot_analysis(phase_id, outcome) do
    with {:ok, uuid} <- Persistence.cast_id(phase_id, :accept_pilot_analysis, :phase),
         {:ok, params} <-
           Persistence.encode_json(
             PilotOutcome,
             :t,
             outcome,
             :accept_pilot_analysis,
             :pilot_outcome
           ) do
      Persistence.tx(:accept_pilot_analysis, :phase, fn ->
        analyzed_pilot(uuid, outcome, params, :accept_pilot_analysis)
      end)
    end
  end

  defp analyzed_pilot(phase_id, outcome, params, operation) do
    with {:ok, phase} <- Persistence.stored_phase(phase_id, operation),
         :ok <- expect_phase(phase, :pilot_analysis, operation),
         {:ok, execution} <- lock_execution(phase.study_execution_id, operation),
         {:ok, accepted} <-
           Persistence.decode_optional_json(
             PilotOutcome,
             :t,
             execution.pilot_outcome,
             operation,
             :pilot_outcome
           ) do
      accept = fn -> advance(execution, :pilot_analyzed, %{pilot_outcome: params}, operation) end
      class = classify(execution.state, :analyzing_pilot)

      settle_accepted(execution, class, accepted, outcome, :pilot_outcome, operation, accept)
    end
  end

  @spec accept_final_analysis(Ecto.UUID.t(), CorrectedFamily.t(), Timing.t()) ::
          Persistence.response(Persistence.lifecycle_context())
  def accept_final_analysis(phase_id, family, timing) do
    with {:ok, uuid} <- Persistence.cast_id(phase_id, :accept_final_analysis, :phase),
         {:ok, params} <- final_output(family, timing) do
      Persistence.tx(:accept_final_analysis, :phase, fn ->
        analyzed_final(uuid, family, timing, params, :accept_final_analysis)
      end)
    end
  end

  defp analyzed_final(phase_id, family, timing, params, operation) do
    with {:ok, phase} <- Persistence.stored_phase(phase_id, operation),
         :ok <- expect_phase(phase, :final_analysis, operation),
         {:ok, execution} <- lock_execution(phase.study_execution_id, operation) do
      settle_final(execution, family, timing, params, operation)
    end
  end

  defp settle_final(execution, family, timing, params, operation) do
    accept = fn -> insert_and_advance(execution, params, operation) end
    class = classify(execution.state, :analyzing_final)

    case Persistence.stored_result(execution.id, operation) do
      {:ok, nil} ->
        settle_accepted(execution, class, nil, {family, timing}, :result, operation, accept)

      {:ok, stored} ->
        compare_result(execution, stored, family, timing, operation)

      {:error, _failure} = failure ->
        failure
    end
  end

  defp compare_result(execution, stored, family, timing, operation) do
    if {stored.family, stored.timing} == {family, timing} do
      current(execution, operation)
    else
      {:error, Persistence.error(:conflict, operation, :result, :different_value)}
    end
  end

  defp insert_and_advance(execution, params, operation) do
    with {:ok, %Result{}} <- insert_result(execution.id, params, operation) do
      advance(execution, :final_analyzed, %{}, operation)
    end
  end

  # --- approval -----------------------------------------------------------

  # The lifecycle state decides whether an approval can act at all, so the state
  # is classified before the operator intent is resolved.
  @spec accept_approval(Ecto.UUID.t(), Study.approval()) ::
          Persistence.response(Persistence.lifecycle_context())
  def accept_approval(execution_id, approval) do
    with {:ok, uuid} <- Persistence.cast_id(execution_id, :accept_approval, :execution) do
      Persistence.tx(:accept_approval, :execution, fn ->
        approved_execution(uuid, approval, :accept_approval)
      end)
    end
  end

  defp approved_execution(execution_id, approval, operation) do
    with {:ok, execution} <- lock_execution(execution_id, operation),
         {:ok, accepted} <-
           Persistence.decode_optional_json(
             Selection,
             :t,
             execution.selection,
             operation,
             :selection
           ) do
      settle_approval(
        execution,
        approval,
        classify(execution.state, :awaiting_final),
        accepted,
        operation
      )
    end
  end

  defp settle_approval(_execution, _approval, :early, _accepted, operation) do
    {:error, Persistence.error(:conflict, operation, :execution, :not_awaiting_final)}
  end

  defp settle_approval(_execution, _approval, :aborted, nil, operation) do
    {:error, Persistence.error(:conflict, operation, :selection, :late_acceptance)}
  end

  defp settle_approval(_execution, _approval, :later, nil, operation) do
    {:error, Persistence.error(:storage, operation, :selection, :missing_accepted_value)}
  end

  defp settle_approval(execution, approval, class, accepted, operation) do
    with {:ok, revision} <- Persistence.revision_by_id(execution.study_revision_id, operation),
         {:ok, selection} <-
           approval_selection(execution, approval, revision.definition, operation),
         {:ok, params} <-
           Persistence.encode_json(Selection, :t, selection, operation, :selection) do
      accept = fn -> advance(execution, :resume, %{selection: params}, operation) end

      settle_accepted(execution, class, accepted, selection, :selection, operation, accept)
    end
  end

  # The immutable definition owns the declared candidate counts, so the operator
  # supplies an intent only.
  defp approval_selection(%Execution{pilot_outcome: nil}, _approval, _definition, operation) do
    {:error, Persistence.error(:storage, operation, :pilot_outcome, :missing_accepted_value)}
  end

  defp approval_selection(%Execution{pilot_outcome: stored}, approval, definition, operation) do
    with {:ok, outcome} <-
           Persistence.decode_json(PilotOutcome, :t, stored, operation, :pilot_outcome) do
      resolve_selection(outcome, approval, definition, operation)
    end
  end

  # A recommended outcome names a declared candidate. An accepted recommendation
  # that disagrees with its declared candidate is a broken invariant instead of an
  # operator error.
  defp resolve_selection(
         %PilotOutcome{outcome: :recommended} = outcome,
         :recommended,
         definition,
         operation
       ) do
    case declared_candidate(definition, outcome.candidate_id) do
      %Candidate{} = candidate ->
        settle_recommendation(candidate, outcome, operation)

      nil ->
        {:error,
         Persistence.error(
           :storage,
           operation,
           :pilot_outcome,
           {:undeclared_candidate, outcome.candidate_id}
         )}
    end
  end

  # An insufficient outcome accepts an operator-selected declared candidate.
  defp resolve_selection(
         %PilotOutcome{outcome: :insufficient},
         {:override_insufficient, candidate_id},
         definition,
         operation
       ) do
    case declared_candidate(definition, candidate_id) do
      %Candidate{} = candidate ->
        {:ok, selection_from_candidate(candidate)}

      nil ->
        {:error,
         Persistence.error(:conflict, operation, :approval, {:undeclared_candidate, candidate_id})}
    end
  end

  defp resolve_selection(_outcome, _approval, _definition, operation) do
    {:error, Persistence.error(:conflict, operation, :approval, :mismatched_approval)}
  end

  defp settle_recommendation(%Candidate{} = candidate, %PilotOutcome{} = outcome, operation) do
    if candidate.plan_count_per_side == outcome.plan_count_per_side and
         candidate.attacks_per_plan == outcome.attacks_per_plan do
      {:ok, selection_from_candidate(candidate)}
    else
      {:error,
       Persistence.error(
         :storage,
         operation,
         :pilot_outcome,
         {:inconsistent_recommendation, candidate.id}
       )}
    end
  end

  defp selection_from_candidate(%Candidate{} = candidate) do
    %Selection{
      candidate_id: candidate.id,
      plan_count_per_side: candidate.plan_count_per_side,
      attacks_per_plan: candidate.attacks_per_plan
    }
  end

  defp declared_candidate(%Definition{pilot: %{candidates: candidates}}, candidate_id)
       when is_list(candidates) do
    Enum.find(candidates, &(&1.id == candidate_id))
  end

  # --- failure and cancellation -------------------------------------------

  @spec fail_phase(Ecto.UUID.t(), StudyError.t()) ::
          Persistence.response(Persistence.lifecycle_context())
  def fail_phase(phase_id, public_error) do
    with {:ok, uuid} <- Persistence.cast_id(phase_id, :fail_phase, :phase),
         {:ok, params} <-
           Persistence.encode_json(
             StudyError,
             :t,
             public_error,
             :fail_phase,
             :execution_error
           ) do
      Persistence.tx(:fail_phase, :phase, fn -> failed_phase(uuid, params, :fail_phase) end)
    end
  end

  defp failed_phase(phase_id, params, operation) do
    with {:ok, phase} <- Persistence.stored_phase(phase_id, operation),
         {:ok, execution} <- lock_execution(phase.study_execution_id, operation) do
      settle_failure(execution, phase, params, operation)
    end
  end

  defp settle_failure(execution, phase, params, operation) do
    cond do
      terminal?(execution.state) ->
        current(execution, operation)

      phase_for_state(execution.state) == phase.phase ->
        advance(execution, :fail, %{error: params}, operation)

      true ->
        {:error, Persistence.error(:conflict, operation, :phase, :stale_phase)}
    end
  end

  # A terminal execution keeps its stored status, so a late phase completion
  # cannot advance a cancelled execution.
  @spec cancel_execution(Ecto.UUID.t()) :: Persistence.response(Persistence.lifecycle_context())
  def cancel_execution(execution_id) do
    with {:ok, uuid} <- Persistence.cast_id(execution_id, :cancel_execution, :execution) do
      Persistence.tx(:cancel_execution, :execution, fn ->
        cancelled_execution(uuid, :cancel_execution)
      end)
    end
  end

  defp cancelled_execution(execution_id, operation) do
    with {:ok, execution} <- lock_execution(execution_id, operation) do
      if terminal?(execution.state) do
        current(execution, operation)
      else
        advance(execution, :cancel, %{}, operation)
      end
    end
  end

  # --- compare-and-return of one accepted value ---------------------------

  defp settle_accepted(_execution, :expected, nil, _submitted, _resource, _operation, accept),
    do: accept.()

  defp settle_accepted(_execution, :early, _accepted, _submitted, _resource, operation, _accept) do
    {:error, Persistence.error(:conflict, operation, :execution, :early_acceptance)}
  end

  defp settle_accepted(_execution, :aborted, nil, _submitted, resource, operation, _accept) do
    {:error, Persistence.error(:conflict, operation, resource, :late_acceptance)}
  end

  defp settle_accepted(_execution, :later, nil, _submitted, resource, operation, _accept) do
    {:error, Persistence.error(:storage, operation, resource, :missing_accepted_value)}
  end

  # An equal accepted value returns the current state without a second
  # transition.
  defp settle_accepted(execution, _class, accepted, submitted, _resource, operation, _accept)
       when accepted == submitted do
    current(execution, operation)
  end

  defp settle_accepted(_execution, _class, _accepted, _submitted, resource, operation, _accept) do
    {:error, Persistence.error(:conflict, operation, resource, :different_value)}
  end

  # --- lifecycle transitions ---------------------------------------------

  defp advance(execution, event, changes, operation) do
    with {:ok, next_state} <- lifecycle_transition(execution.state, event, operation),
         {:ok, updated} <-
           update_execution(execution, Map.put(changes, :state, next_state), operation),
         {:ok, phase} <- enter_phase(updated, operation) do
      Persistence.build_lifecycle_context(updated, phase, operation)
    end
  end

  defp current(execution, operation) do
    with {:ok, phase} <- required_phase(execution, operation) do
      Persistence.build_lifecycle_context(execution, phase, operation)
    end
  end

  defp lifecycle_transition(state, event, operation) do
    case Lifecycle.transition(state, event) do
      {:ok, next_state} ->
        {:ok, next_state}

      {:error, :invalid_transition} ->
        {:error,
         Persistence.error(:storage, operation, :execution, {:invalid_transition, state, event})}
    end
  end

  defp update_execution(execution, changes, operation) do
    case Repo.update(Changeset.change(execution, changes)) do
      {:ok, %Execution{} = updated} ->
        {:ok, updated}

      {:error, changeset} ->
        {:error, Persistence.error(:storage, operation, :execution, changeset)}
    end
  end

  defp insert_execution(revision_id, operation) do
    execution = %Execution{study_revision_id: revision_id, state: Lifecycle.initial_state()}

    case Repo.insert(execution) do
      {:ok, %Execution{} = row} ->
        {:ok, row}

      {:error, changeset} ->
        {:error, Persistence.error(:storage, operation, :execution, changeset)}
    end
  end

  defp lock_execution(id, operation) do
    case Repo.one(from e in Execution, where: e.id == ^id, lock: "FOR UPDATE") do
      %Execution{} = execution -> {:ok, execution}
      nil -> {:error, Persistence.error(:not_found, operation, :execution, nil)}
    end
  end

  # Every active state owns its phase identity (Q83).
  defp enter_phase(%Execution{id: id, state: state}, operation) do
    case phase_for_state(state) do
      nil -> {:ok, nil}
      kind -> ensure_phase(id, kind, operation)
    end
  end

  defp required_phase(%Execution{id: id, state: state}, operation) do
    case phase_for_state(state) do
      nil -> {:ok, nil}
      kind -> stored_phase_kind(id, kind, operation)
    end
  end

  defp stored_phase_kind(execution_id, kind, operation) do
    case Repo.get_by(Phase, study_execution_id: execution_id, phase: kind) do
      %Phase{} = phase -> {:ok, phase}
      nil -> {:error, Persistence.error(:storage, operation, :phase, :missing_active_phase)}
    end
  end

  defp ensure_phase(execution_id, kind, operation) do
    case Repo.get_by(Phase, study_execution_id: execution_id, phase: kind) do
      %Phase{} = phase -> {:ok, phase}
      nil -> insert_phase(execution_id, kind, operation)
    end
  end

  defp insert_phase(execution_id, kind, operation) do
    case Repo.insert(%Phase{study_execution_id: execution_id, phase: kind}) do
      {:ok, %Phase{} = phase} -> {:ok, phase}
      {:error, changeset} -> {:error, Persistence.error(:storage, operation, :phase, changeset)}
    end
  end

  defp phase_for_state(:collecting_pilot), do: :pilot_collection
  defp phase_for_state(:analyzing_pilot), do: :pilot_analysis
  defp phase_for_state(:collecting_final), do: :final_collection
  defp phase_for_state(:analyzing_final), do: :final_analysis
  defp phase_for_state(_state), do: nil

  # Classify one lifecycle state against the state of one command.
  #
  # `successful_progress/1` declares the successful chain only, so no total order
  # over failed and cancelled states is needed. A succeeded execution stays on
  # that chain, so a missing accepted value there is an internal invariant
  # failure.
  defp classify(state, expected_state) do
    cond do
      state == expected_state -> :expected
      abort?(state) -> :aborted
      successful_progress(state) > successful_progress(expected_state) -> :later
      true -> :early
    end
  end

  defp successful_progress(:collecting_pilot), do: 0
  defp successful_progress(:analyzing_pilot), do: 1
  defp successful_progress(:awaiting_final), do: 2
  defp successful_progress(:collecting_final), do: 3
  defp successful_progress(:analyzing_final), do: 4
  defp successful_progress(:succeeded), do: 5

  # Only an aborted execution can end without its lifecycle successor.
  defp abort?(state), do: state in [:failed, :cancelled]

  defp terminal?(state), do: state in [:succeeded, :failed, :cancelled]

  # --- private record helpers --------------------------------------------

  defp expect_phase(%Phase{phase: kind}, kind, _operation), do: :ok

  defp expect_phase(%Phase{}, _kind, operation) do
    {:error, Persistence.error(:conflict, operation, :phase, :unexpected_phase)}
  end

  defp final_output(family, timing) do
    with {:ok, family_params} <-
           Persistence.encode_json(
             CorrectedFamily,
             :t,
             family,
             :accept_final_analysis,
             :final_family
           ),
         {:ok, timing_params} <-
           Persistence.encode_json(Timing, :t, timing, :accept_final_analysis, :final_timing) do
      {:ok, %{family: family_params, timing: timing_params}}
    end
  end

  defp insert_result(execution_id, params, operation) do
    %Result{}
    |> Changeset.change(Map.put(params, :study_execution_id, execution_id))
    |> Changeset.unique_constraint(:study_execution_id,
      name: :evaluation2_study_results_study_execution_id_index
    )
    |> Repo.insert()
    |> case do
      {:ok, %Result{} = result} -> {:ok, result}
      {:error, changeset} -> {:error, Persistence.error(:storage, operation, :result, changeset)}
    end
  end
end
