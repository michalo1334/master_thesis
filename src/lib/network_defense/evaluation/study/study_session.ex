defmodule NetworkDefense.Evaluation.StudySession do
  @moduledoc """
  Ephemeral state for one browser study document.

  A session locks the saved specification identity and the exact Pilot
  tier-run mapping when Pilot starts. After an eligible Pilot, the browser
  selects a separate Final mapping for the final seed schedule. The session
  locks that Final mapping when Final starts, so a Final retry reuses the same
  evidence. Pilot and Final run IDs must not overlap.

  The document never edits locked inputs. Pilot and Final results live here
  only; the LiveView discards the session on close or disconnect.

  Every task attempt is an explicit `StudyAttempt` struct. The session changes
  state only when the owner consumes the attempt that the message identity
  points at. A stale message returns `:stale` and leaves the session untouched.
  The attempt identity is a browser-safe opaque string, so the same value pins
  the browser document to exactly one attempt.

  A non-nil attempt is active until the owner consumes its result or `:DOWN`
  message. The session never calls `Process.alive?/1`, because a task can send
  its result and exit before the owner schedules.

  A new Pilot attempt clears any earlier Pilot eligibility and its Final
  result. A failed Pilot attempt clears them too. A failed Final attempt keeps
  the eligible Pilot so Final can run again. The session keeps parsed analysis
  only; it never keeps the raw result ZIP after delivery.
  """

  alias NetworkDefense.Evaluation.StudyAttempt
  alias NetworkDefense.Evaluation.StudyRunner

  @enforce_keys [:document_id, :specification_id, :study_id, :specification_version, :tier_runs]
  defstruct [
    :document_id,
    :specification_id,
    :study_id,
    :specification_version,
    :tier_runs,
    :final_tier_runs,
    :attempt,
    :mode,
    :phase,
    :error,
    pilot: nil,
    final: nil
  ]

  @type stored_result :: %{analysis: map(), eligible: boolean() | nil}

  @type error :: %{reason: term(), phase: StudyRunner.phase() | nil}

  @type t :: %__MODULE__{
          document_id: String.t(),
          specification_id: String.t(),
          study_id: String.t(),
          specification_version: pos_integer() | nil,
          tier_runs: [StudyRunner.tier_run()],
          final_tier_runs: [StudyRunner.tier_run()] | nil,
          attempt: StudyAttempt.t() | nil,
          mode: StudyRunner.mode() | nil,
          phase: StudyRunner.phase() | nil,
          error: error() | nil,
          pilot: stored_result() | nil,
          final: stored_result() | nil
        }

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs), do: struct!(__MODULE__, attrs)

  @doc "Reports whether the locked specification and mapping match the request."
  @spec matches_locks?(t(), String.t(), [StudyRunner.tier_run()]) :: boolean()
  def matches_locks?(%__MODULE__{} = session, specification_id, tier_runs) do
    session.specification_id == specification_id and session.tier_runs == tier_runs
  end

  @doc "Returns the locked tier mapping for one mode."
  @spec mode_tier_runs(t(), StudyRunner.mode()) :: [StudyRunner.tier_run()]
  def mode_tier_runs(%__MODULE__{final_tier_runs: final_tier_runs}, :final),
    do: final_tier_runs || []

  def mode_tier_runs(%__MODULE__{tier_runs: tier_runs}, :pilot), do: tier_runs

  @doc "Returns the locked Final mapping, or `nil` before the first Final start."
  @spec final_tier_runs(t()) :: [StudyRunner.tier_run()] | nil
  def final_tier_runs(%__MODULE__{final_tier_runs: final_tier_runs}), do: final_tier_runs

  @doc "Reports whether the Final mapping is locked."
  @spec final_mapping_locked?(t()) :: boolean()
  def final_mapping_locked?(%__MODULE__{final_tier_runs: final_tier_runs}),
    do: is_list(final_tier_runs)

  @doc "Locks the Final mapping once, so a later Final retry reuses it."
  @spec lock_final(t(), [StudyRunner.tier_run()]) :: t()
  def lock_final(%__MODULE__{final_tier_runs: nil} = session, tier_runs)
      when is_list(tier_runs) do
    if tier_runs == [], do: session, else: %{session | final_tier_runs: tier_runs}
  end

  def lock_final(%__MODULE__{} = session, _tier_runs), do: session

  @doc "Reports whether any Final run ID also appears in the Pilot mapping."
  @spec overlaps_pilot?(t(), [StudyRunner.tier_run()]) :: boolean()
  def overlaps_pilot?(%__MODULE__{} = session, tier_runs) when is_list(tier_runs) do
    pilot_ids = session.tier_runs |> Enum.map(&elem(&1, 1)) |> MapSet.new()
    Enum.any?(tier_runs, fn {_tier, run_id} -> MapSet.member?(pilot_ids, run_id) end)
  end

  @doc """
  Reports whether an attempt is active.

  A non-nil attempt counts as active until the owner consumes it. This ignores
  the task liveness on purpose.
  """
  @spec running?(t()) :: boolean()
  def running?(%__MODULE__{attempt: %StudyAttempt{}}), do: true
  def running?(%__MODULE__{}), do: false

  @spec attempt(t()) :: StudyAttempt.t() | nil
  def attempt(%__MODULE__{attempt: attempt}), do: attempt

  @spec attempt_id(t()) :: String.t() | nil
  def attempt_id(%__MODULE__{attempt: %StudyAttempt{id: id}}), do: id
  def attempt_id(%__MODULE__{}), do: nil

  @doc "Locks one attempt and invalidates earlier Pilot eligibility for a Pilot start."
  @spec start_attempt(t(), StudyAttempt.t()) :: t()
  def start_attempt(%__MODULE__{} = session, %StudyAttempt{mode: mode} = attempt) do
    session
    |> Map.put(:attempt, attempt)
    |> Map.put(:mode, mode)
    |> Map.put(:phase, :building_bundle)
    |> Map.put(:error, nil)
    |> invalidate_pilot_results(mode)
  end

  @doc "Sets the phase for the matching attempt and ignores a stale attempt."
  @spec set_phase(t(), String.t(), StudyRunner.phase()) :: {:ok, t()} | :stale
  def set_phase(%__MODULE__{attempt: %StudyAttempt{id: id}} = session, id, phase) do
    {:ok, %{session | phase: phase}}
  end

  def set_phase(%__MODULE__{}, _attempt_id, _phase), do: :stale

  @doc """
  Stores a parsed result for the matching attempt.

  Returns the consumed attempt so the caller emits exactly one terminal
  lifecycle event.
  """
  @spec consume_result(t(), String.t(), stored_result()) ::
          {:ok, t(), StudyAttempt.t()} | :stale
  def consume_result(
        %__MODULE__{attempt: %StudyAttempt{id: id, mode: mode}} = session,
        id,
        result
      ) do
    {:ok, store_result(session, mode, result), session.attempt}
  end

  def consume_result(%__MODULE__{}, _attempt_id, _result), do: :stale

  @doc """
  Stores a failure for the matching attempt and keeps the locked inputs.

  A failed Pilot attempt clears earlier Pilot eligibility. A failed Final
  attempt keeps the eligible Pilot.
  """
  @spec consume_failure(t(), String.t(), term()) :: {:ok, t(), StudyAttempt.t()} | :stale
  def consume_failure(
        %__MODULE__{attempt: %StudyAttempt{id: id, mode: mode} = attempt} = session,
        id,
        reason
      ) do
    session = %{session | attempt: nil, error: %{reason: reason, phase: session.phase}}
    {:ok, invalidate_pilot_results(session, mode), attempt}
  end

  def consume_failure(%__MODULE__{}, _attempt_id, _reason), do: :stale

  @doc "Consumes the attempt that the monitor reference points at as a crash."
  @spec consume_down(t(), reference()) :: {:ok, t(), StudyAttempt.t()} | :stale
  def consume_down(%__MODULE__{attempt: %StudyAttempt{ref: ref}} = session, ref) do
    consume_failure(session, session.attempt.id, :internal_error)
  end

  def consume_down(%__MODULE__{}, _ref), do: :stale

  @doc """
  Clears the active attempt and returns it for one cancellation event.

  A session with no active attempt returns `nil`, so a consumed result cannot
  also emit a cancellation.
  """
  @spec cancel(t()) :: {t(), StudyAttempt.t() | nil}
  def cancel(%__MODULE__{attempt: %StudyAttempt{}} = session) do
    {%{session | attempt: nil}, session.attempt}
  end

  def cancel(%__MODULE__{} = session), do: {session, nil}

  @spec pilot_eligible?(t()) :: boolean()
  def pilot_eligible?(%__MODULE__{pilot: %{eligible: true}}), do: true
  def pilot_eligible?(%__MODULE__{}), do: false

  @doc """
  Reports whether Final may start: eligible Pilot, no active attempt, and no
  stored Final result.
  """
  @spec final_allowed?(t()) :: boolean()
  def final_allowed?(%__MODULE__{} = session) do
    pilot_eligible?(session) and not running?(session) and is_nil(session.final)
  end

  defp store_result(session, :pilot, result) do
    %{session | attempt: nil, phase: :complete, error: nil, pilot: result, final: nil}
  end

  defp store_result(session, :final, result) do
    %{session | attempt: nil, phase: :complete, error: nil, final: result}
  end

  # A new or failed Pilot attempt invalidates earlier eligibility and its
  # Final, because eligibility belongs to one locked Pilot run. Final attempts
  # do not touch Pilot state.
  defp invalidate_pilot_results(session, :pilot),
    do: %{session | pilot: nil, final: nil, final_tier_runs: nil}

  defp invalidate_pilot_results(session, :final), do: session
end
