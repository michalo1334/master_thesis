defmodule NetworkDefenseWeb.Dashboard.StudyCoordinator do
  @moduledoc """
  Orchestrates the ephemeral study-document sessions for one dashboard.

  The coordinator owns every study lifecycle transition: it locks inputs,
  starts and monitors one task attempt per document, consumes attempt results
  and `:DOWN` messages exactly once, and emits one terminal lifecycle telemetry
  event per consumed attempt. `NetworkDefenseWeb.DashboardLive` only validates
  wire contracts, forwards `handle_info` messages, and pushes the returned
  event tuples.

  Each task attempt is a `StudyAttempt` struct with a unique, browser-safe
  opaque identity. Phase and result messages carry that identity, so a message
  from a replaced attempt cannot change the current session. The accepted start
  reply carries the same identity, so the browser rejects an event from an
  earlier attempt in the same mode. The coordinator does not call
  `Process.alive?/1`; a non-nil attempt is active until consumed.

  Results stay in the session as parsed analysis only. The coordinator encodes
  the result ZIP for the ready event once and never keeps the raw bytes.
  `NetworkDefense.Evaluation.AnalysisLimits.browser_result_bytes/0` bounds the
  ZIP size; the supervised task applies that guard before it sends its result,
  so an oversized archive never reaches the LiveView mailbox. Such a result
  arrives as the `:result_too_large` error and carries no archive bytes.
  """

  require Logger

  alias NetworkDefense.Evaluation.AnalysisLimits
  alias NetworkDefense.Evaluation.StudyAttempt
  alias NetworkDefense.Evaluation.StudyRunner
  alias NetworkDefense.Evaluation.StudySession
  alias NetworkDefense.Evaluation.StudySpecification
  alias NetworkDefense.Evaluation.StudySpecifications
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyAnalysisErrorEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyAnalysisProgressEvent
  alias NetworkDefenseWeb.Contracts.Dashboard.Evaluation.StudyAnalysisReadyEvent
  alias OpentelemetryProcessPropagator.Task.Supervisor, as: TaskSupervisor

  @task_supervisor NetworkDefense.TaskSupervisor

  @type push :: {String.t(), module(), map()}
  @type sessions :: %{optional(String.t()) => StudySession.t()}

  @type start_request :: %{
          document_id: String.t(),
          specification_id: String.t() | nil,
          tier_runs: [StudyRunner.tier_run()]
        }

  @type result ::
          {:ok, %{archive: binary(), analysis: map(), eligible: boolean() | nil}}
          | {:error, term()}

  @spec new() :: sessions()
  def new, do: %{}

  @doc """
  Locks inputs and starts one monitored attempt for a document.

  A Pilot request locks the specification and the Pilot mapping. A Final
  request must carry the separate Final mapping. The coordinator rejects
  overlap with the Pilot mapping and locks the Final mapping on the first
  accepted Final start, so a Final retry reuses the same evidence.

  The accepted reply carries the attempt identity, so the browser can require
  exact document/mode/attempt correlation on every later event.
  """
  @spec start(sessions(), StudyRunner.mode(), start_request()) ::
          {:ok, sessions(), String.t(), String.t()} | {:error, term()}
  def start(sessions, :pilot, request) when is_map(sessions) and is_map(request),
    do: start_pilot(sessions, request)

  def start(sessions, :final, request) when is_map(sessions) and is_map(request),
    do: start_final(sessions, request)

  @doc "Applies one phase message for the matching attempt."
  @spec handle_phase(sessions(), String.t(), String.t(), StudyRunner.phase()) ::
          {sessions(), [push()]}
  def handle_phase(sessions, document_id, attempt_id, phase) do
    with %StudySession{} = session <- Map.get(sessions, document_id),
         {:ok, session} <- StudySession.set_phase(session, attempt_id, phase) do
      {Map.put(sessions, document_id, session), [progress_push(session, phase)]}
    else
      _stale_or_missing -> {sessions, []}
    end
  end

  @doc """
  Consumes one task result for the matching attempt.

  A result at or below the browser-delivery limit becomes a ready event that
  carries the exact ZIP bytes as base64. A larger result becomes a
  `result_too_large` error event.
  """
  @spec handle_result(sessions(), String.t(), String.t(), result()) :: {sessions(), [push()]}
  def handle_result(sessions, document_id, attempt_id, result) do
    case Map.get(sessions, document_id) do
      %StudySession{} = session ->
        apply_result(sessions, document_id, session, attempt_id, result)

      nil ->
        {sessions, []}
    end
  end

  @doc """
  Consumes the monitor message for the matching attempt.

  A reachable `:DOWN` means the task ended without a result, so the attempt
  fails with an internal error and one failed lifecycle event.
  """
  @spec handle_down(sessions(), reference()) :: {sessions(), [push()]}
  def handle_down(sessions, ref) when is_reference(ref) do
    case find_by_ref(sessions, ref) do
      {document_id, session} -> apply_down(sessions, document_id, session, ref)
      nil -> {sessions, []}
    end
  end

  @doc """
  Removes a document, cancels its active attempt, and returns the close status.

  The close status is `:not_found` when no session exists.
  """
  @spec close(sessions(), String.t()) :: {sessions(), :closed | :not_found}
  def close(sessions, document_id) do
    case Map.pop(sessions, document_id) do
      {nil, _sessions} ->
        {sessions, :not_found}

      {session, remaining} ->
        cancel_attempt(session)
        {remaining, :closed}
    end
  end

  @doc "Cancels every active attempt. The LiveView calls this from `terminate/2`."
  @spec terminate(sessions()) :: :ok
  def terminate(sessions) do
    Enum.each(sessions, fn {_document_id, session} -> cancel_attempt(session) end)
    :ok
  end

  defp start_pilot(sessions, request) do
    with :ok <- require_pilot_selection(request),
         {:ok, specification} <- fetch_specification(request.specification_id),
         :ok <- validate_selection(specification.id, request.tier_runs, :pilot),
         {:ok, session} <- lock_or_resume(sessions, request.document_id, specification, request),
         {:ok, session} <- start_task(session, :pilot) do
      accepted(sessions, session)
    end
  end

  defp start_final(sessions, request) do
    with {:ok, session} <- fetch_session(sessions, request.document_id),
         :ok <- require_final_available(session),
         :ok <- require_final_specification(session, request),
         {:ok, tier_runs} <- resolve_final_mapping(session, request),
         :ok <- validate_selection(session.specification_id, tier_runs, :final),
         {:ok, session} <- start_task(StudySession.lock_final(session, tier_runs), :final) do
      accepted(sessions, session)
    end
  end

  # The Final mapping belongs to the session's locked specification. An
  # explicit different specification is a different document, so Final cannot
  # reuse this eligible Pilot.
  defp require_final_specification(%StudySession{} = session, request) do
    case Map.get(request, :specification_id) do
      nil ->
        :ok

      specification_id ->
        if specification_id == session.specification_id, do: :ok, else: {:error, :document_locked}
    end
  end

  # The first Final start locks the browser-selected Final mapping. A later
  # Final start must repeat that exact mapping, so a changed mapping cannot
  # reuse the eligible Pilot behind the user's back.
  defp resolve_final_mapping(%StudySession{final_tier_runs: nil} = session, request) do
    case normalise_tier_runs(request) do
      [] -> {:error, :invalid_request}
      tier_runs -> validate_final_overlap(session, tier_runs)
    end
  end

  defp resolve_final_mapping(%StudySession{} = session, request) do
    if normalise_tier_runs(request) == session.final_tier_runs do
      {:ok, session.final_tier_runs}
    else
      {:error, :document_locked}
    end
  end

  defp validate_final_overlap(%StudySession{} = session, tier_runs) do
    if StudySession.overlaps_pilot?(session, tier_runs) do
      {:error, :run_overlap}
    else
      {:ok, tier_runs}
    end
  end

  defp normalise_tier_runs(%{tier_runs: tier_runs}) when is_list(tier_runs),
    do: Enum.flat_map(tier_runs, &normalise_tier_run/1)

  defp normalise_tier_runs(_request), do: []

  defp normalise_tier_run({tier, run_id}) when is_binary(tier) and is_binary(run_id),
    do: [{tier, run_id}]

  defp normalise_tier_run(%{tier: tier, run_id: run_id})
       when is_binary(tier) and is_binary(run_id),
       do: [{tier, run_id}]

  defp normalise_tier_run(_tier_run), do: []

  defp accepted(sessions, session) do
    {:ok, Map.put(sessions, session.document_id, session), session.document_id,
     StudySession.attempt_id(session)}
  end

  defp require_pilot_selection(%{specification_id: specification_id, tier_runs: [_ | _]})
       when is_binary(specification_id),
       do: :ok

  defp require_pilot_selection(_request), do: {:error, :invalid_request}

  # This is the authoritative start boundary. It repeats the full preflight
  # before a new session or Final mapping is locked, so an invalid mapping
  # cannot become a retry-only lock after asynchronous bundle construction.
  defp validate_selection(specification_id, tier_runs, mode) do
    case StudyRunner.preflight(specification_id, tier_runs, mode) do
      {:ok, _preflight} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp fetch_specification(specification_id) when is_binary(specification_id) do
    case StudySpecifications.get(specification_id) do
      %StudySpecification{} = specification -> {:ok, specification}
      nil -> {:error, :specification_not_found}
    end
  end

  defp lock_or_resume(sessions, document_id, specification, request) do
    case Map.get(sessions, document_id) do
      nil ->
        {:ok, new_session(document_id, specification, request.tier_runs)}

      %StudySession{} = session ->
        cond do
          StudySession.running?(session) ->
            {:error, :already_running}

          StudySession.matches_locks?(session, specification.id, request.tier_runs) ->
            {:ok, session}

          true ->
            {:error, :document_locked}
        end
    end
  end

  defp fetch_session(sessions, document_id) do
    case Map.get(sessions, document_id) do
      %StudySession{} = session -> {:ok, session}
      nil -> {:error, :document_not_found}
    end
  end

  defp require_final_available(%StudySession{} = session) do
    cond do
      StudySession.running?(session) -> {:error, :already_running}
      StudySession.final_allowed?(session) -> :ok
      true -> {:error, :final_not_available}
    end
  end

  defp new_session(document_id, specification, tier_runs) do
    StudySession.new(%{
      document_id: document_id,
      specification_id: specification.id,
      study_id: specification.study_id,
      specification_version: specification.specification_version,
      tier_runs: tier_runs
    })
  end

  defp start_task(session, mode) do
    owner = self()
    attempt_id = StudyAttempt.new_id()

    case TaskSupervisor.start_child(@task_supervisor, fn ->
           run_task(owner, attempt_id, session, mode)
         end) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        attempt = StudyAttempt.new(attempt_id, mode, pid, ref)
        {:ok, StudySession.start_attempt(session, attempt)}

      {:error, _reason} ->
        {:error, :internal_error}
    end
  end

  # The task reports every phase and its final result. It does not emit the
  # terminal lifecycle event; the owner does that once when it consumes the
  # attempt. A crash reaches the owner as `:DOWN` instead.
  defp run_task(owner, attempt_id, session, mode) do
    StudyRunner.emit_lifecycle(:started, lifecycle_metadata(session, mode))

    on_phase = fn phase -> send(owner, {:study_phase, session.document_id, attempt_id, phase}) end

    result = execute(session, mode, on_phase)
    send(owner, {:study_result, session.document_id, attempt_id, result})
  end

  defp execute(session, mode, on_phase) do
    tier_runs = StudySession.mode_tier_runs(session, mode)

    case StudyRunner.execute(session.specification_id, tier_runs, mode, on_phase) do
      {:ok, %{archive: archive, analysis: analysis}} ->
        deliverable_result(archive, analysis, mode)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The browser-delivery guard runs here, inside the supervised task, before
  # any archive byte crosses to the LiveView mailbox. An oversized result
  # becomes a stable error that carries no archive bytes.
  defp deliverable_result(archive, analysis, mode) do
    if AnalysisLimits.browser_deliverable?(archive) do
      {:ok,
       %{
         archive: archive,
         analysis: analysis,
         eligible: StudyRunner.pilot_eligible?(mode, analysis)
       }}
    else
      {:error, :result_too_large}
    end
  end

  defp apply_result(sessions, document_id, session, attempt_id, result) do
    case classify_result(result) do
      {:ready, %{archive: archive, analysis: analysis, eligible: eligible}} ->
        complete_attempt(sessions, document_id, session, attempt_id, %{
          analysis: analysis,
          eligible: eligible,
          archive: archive
        })

      {:error, reason} ->
        fail_attempt(sessions, document_id, session, attempt_id, reason)
    end
  end

  defp classify_result({:ok, %{archive: archive} = result}) when is_binary(archive) do
    if AnalysisLimits.browser_deliverable?(archive) do
      {:ready, result}
    else
      {:error, :result_too_large}
    end
  end

  defp classify_result({:error, reason}), do: {:error, reason}
  defp classify_result(_result), do: {:error, :internal_error}

  defp complete_attempt(sessions, document_id, session, attempt_id, delivered) do
    stored = Map.take(delivered, [:analysis, :eligible])

    case StudySession.consume_result(session, attempt_id, stored) do
      {:ok, session, attempt} ->
        emit_terminal(:completed, session, attempt)

        push =
          ready_push(session, attempt, delivered.analysis, delivered.eligible, delivered.archive)

        {Map.put(sessions, document_id, session), [push]}

      :stale ->
        {sessions, []}
    end
  end

  defp fail_attempt(sessions, document_id, session, attempt_id, reason) do
    case StudySession.consume_failure(session, attempt_id, reason) do
      {:ok, session, attempt} ->
        emit_terminal(:failed, session, attempt)
        {Map.put(sessions, document_id, session), [error_push(session, attempt)]}

      :stale ->
        {sessions, []}
    end
  end

  defp apply_down(sessions, document_id, session, ref) do
    case StudySession.consume_down(session, ref) do
      {:ok, session, attempt} ->
        Logger.error("study analysis task ended without a result", document_id: document_id)
        emit_terminal(:failed, session, attempt)
        {Map.put(sessions, document_id, session), [error_push(session, attempt)]}

      :stale ->
        {sessions, []}
    end
  end

  defp find_by_ref(sessions, ref) do
    Enum.find_value(sessions, fn {document_id, session} ->
      case StudySession.attempt(session) do
        %StudyAttempt{ref: ^ref} -> {document_id, session}
        _attempt -> nil
      end
    end)
  end

  defp cancel_attempt(%StudySession{} = session) do
    {_session, attempt} = StudySession.cancel(session)

    if attempt do
      TaskSupervisor.terminate_child(@task_supervisor, attempt.pid)
      emit_terminal(:cancelled, session, attempt)
    end

    :ok
  end

  defp emit_terminal(outcome, session, attempt) do
    StudyRunner.emit_attempt_lifecycle(
      outcome,
      attempt,
      lifecycle_metadata(session, attempt.mode)
    )
  end

  defp lifecycle_metadata(session, mode) do
    %{
      study_id: session.study_id,
      specification_version: session.specification_version,
      mode: StudyRunner.mode_to_wire(mode),
      tier_count: length(StudySession.mode_tier_runs(session, mode))
    }
  end

  defp progress_push(session, phase) do
    {"study_analysis_progress", StudyAnalysisProgressEvent,
     %{
       document_id: session.document_id,
       mode: StudyRunner.mode_to_wire(session.mode),
       attempt_id: StudySession.attempt_id(session),
       phase: StudyRunner.phase_to_wire(phase)
     }}
  end

  defp ready_push(session, attempt, analysis, eligible, archive) do
    {"study_analysis_ready", StudyAnalysisReadyEvent,
     %{
       document_id: session.document_id,
       mode: StudyRunner.mode_to_wire(attempt.mode),
       attempt_id: attempt.id,
       analysis: analysis,
       archive: Base.encode64(archive),
       pilot_eligible: eligible
     }}
  end

  defp error_push(session, attempt) do
    {"study_analysis_error", StudyAnalysisErrorEvent,
     %{
       document_id: session.document_id,
       mode: StudyRunner.mode_to_wire(attempt.mode),
       attempt_id: attempt.id,
       phase: StudyRunner.phase_to_wire(session.phase),
       error: %{code: Atom.to_string(StudyRunner.wire_error(session.error.reason))}
     }}
  end
end
