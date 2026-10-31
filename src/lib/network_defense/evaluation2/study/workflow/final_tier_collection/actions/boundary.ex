defmodule NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.Boundary do
  @moduledoc false

  # Shared boundary of the Final tier collection Gust tasks.
  #
  # Every task acts for the Gust run it executes. The stored run input names one
  # phase run, the canonical phase-run row of the Final collection phase proves
  # the ownership, and the tier comes from that row, so a task cannot choose its
  # tier.
  #
  # The preparation task stores the tier plan and the clock session. Every later
  # task recovers that stored value, because a second clock session would mix two
  # measurement runs.
  #
  # The measured environment label is re-read at every replica preparation and at
  # the terminal task, so a deployment change during a run stops it.
  #
  # This module also owns the task-level transport of the phase: the prepared
  # result and the replica receipt cross the Gust task boundary as JSON, so their
  # strict codecs live next to the run binding.
  #
  # Every tagged failure is logged and raised as one fixed permanent Gust message
  # by the action. The tagged helpers return the tagged result unchanged, so each
  # action keeps the complete declared result type of its capability.

  require Logger

  alias Gust.Flows
  alias Gust.Flows.Task
  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Evaluation2.Study.Definition.Provenance
  alias NetworkDefense.Evaluation2.Study.Final.TierContract
  alias NetworkDefense.Evaluation2.Study.Final.Timing, as: FinalTiming
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionItem
  alias NetworkDefense.Evaluation2.Study.Persistence.PhaseRun
  alias NetworkDefense.Evaluation2.Study.Randomness
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Selection
  alias NetworkDefense.Evaluation2.Study.Tier
  alias NetworkDefense.Evaluation2.Study.Workflow.ActionBoundary
  alias NetworkDefense.Evaluation2.Study.Workflow.FinalTierCollection.Actions.Prepared

  @prepare_task "prepare_tier_collection"
  @tier_names %{"small" => :small, "medium" => :medium, "large" => :large}
  @prepared_keys ["clock_session", "phase_run_id", "plan_id", "tier"]
  @replica_keys ["plan_selection_us", "replica_position", "simulation_us", "total_us"]

  @context_failure "Evaluation2 Final tier collection context is unavailable"
  @foreign_run_failure "Evaluation2 Final tier collection task acted for another Gust run"
  @foreign_phase_failure "Evaluation2 Final tier collection phase run belongs to another phase"
  @not_canonical_failure "Evaluation2 Final tier collection phase run is not canonical"
  @unknown_tier_failure "Evaluation2 Final tier collection phase run has no declared tier"
  @missing_selection_failure "Evaluation2 Final tier collection has no frozen selection"
  @missing_environment_failure "Evaluation2 Final tier collection has no configured environment label"
  @changed_environment_failure "Evaluation2 Final tier collection environment label changed"
  @task_failure "Evaluation2 Final tier collection task result is unavailable"
  @prepare_failure "Evaluation2 Final tier collection preparation result is invalid"
  @foreign_prepare_failure "Evaluation2 Final tier collection preparation result has another owner"
  @timing_failure "Evaluation2 Final tier collection timing mark failed"

  @typedoc "Phase-run context of one tier collection run with its owning chain."
  @type context :: Persistence.phase_run_context()

  @doc "Return the measured replica positions of one tier."
  @spec measured_positions() :: Range.t()
  def measured_positions, do: 0..4

  @doc """
  Bind a task to the phase run of the acting Gust run.

  The stored run input must decode as the tier collection input, the phase run
  must belong to the Final collection phase, the acting run must own the stored
  link, and the stored row must be the canonical row of its tier.
  """
  @spec run_context(map(), map()) :: {:ok, context()} | {:error, term()}
  def run_context(params, %{run_id: run_id}) do
    with {:ok, input} <- input(params),
         {:ok, context} <- phase_run_context(input.phase_run_id),
         :ok <- expect_final_collection(context.phase),
         :ok <- expect_contract(context.revision.definition),
         :ok <- ActionBoundary.expect_run_id(context.phase_run, run_id, @foreign_run_failure),
         :ok <- expect_canonical(context.phase, context.phase_run) do
      {:ok, context}
    end
  end

  @doc """
  Bind a task to the phase run and to the stored preparation result.

  The preparation result is the only source of the clock session and the tier.
  """
  @spec prepared_run(map(), map()) :: {:ok, {context(), Prepared.t()}} | {:error, term()}
  def prepared_run(params, %{run_id: run_id} = action_context) do
    with {:ok, context} <- run_context(params, action_context),
         {:ok, prepared} <- prepared(run_id),
         :ok <- expect_prepared(prepared, context) do
      {:ok, {context, prepared}}
    end
  end

  @doc "Return the stored tier of one canonical phase run."
  @spec expect_tier(PhaseRun.t()) :: {:ok, Tier.t()} | {:error, :unknown_tier}
  def expect_tier(%PhaseRun{run_key: run_key}) do
    if run_key in Tier.all() do
      {:ok, run_key}
    else
      Logger.error(@unknown_tier_failure, run_key: inspect(run_key))
      {:error, :unknown_tier}
    end
  end

  @doc "Return the frozen Final selection of one execution."
  @spec expect_selection(Persistence.Execution.t()) ::
          {:ok, Selection.t()} | {:error, :missing_selection}
  def expect_selection(%Persistence.Execution{selection: %Selection{} = selection}),
    do: {:ok, selection}

  def expect_selection(%Persistence.Execution{}),
    do: tagged(:missing_selection, @missing_selection_failure)

  @doc """
  Compare the frozen environment label with the configured label.

  A missing configured label and a changed label both stop the run, because a
  timing measurement needs one identified environment for the complete tier.
  """
  @spec expect_environment(Definition.t()) ::
          :ok | {:error, :environment_missing | :environment_changed}
  def expect_environment(%Definition{provenance: %Provenance{environment_label: declared}}) do
    configured = configured_environment_label()

    cond do
      not is_binary(declared) or declared == "" ->
        tagged(:environment_missing, @missing_environment_failure)

      declared == configured ->
        :ok

      is_binary(configured) ->
        tagged(:environment_changed, @changed_environment_failure)

      true ->
        tagged(:environment_missing, @missing_environment_failure)
    end
  end

  @doc "Reject Final re-entry across known method or scientific seed contracts."
  def expect_contract(%Definition{provenance: provenance}) do
    if provenance.method == Definition.method() and
         provenance.seed_contract == Randomness.contract(),
       do: :ok,
       else: tagged(:incompatible_contract, "Evaluation2 Final scientific contract changed")
  end

  @doc "Return the stored preparation result of one run."
  @spec prepared(pos_integer()) :: {:ok, Prepared.t()} | {:error, term()}
  def prepared(run_id) do
    case stored_task(@prepare_task, run_id) do
      {:ok, result} -> decoded_prepared(result)
      {:error, _cause} = failure -> failure
    end
  end

  @doc "Encode the prepared result of one tier run as JSON-safe task parameters."
  @spec prepared_params(Prepared.t()) :: %{required(String.t()) => String.t()}
  def prepared_params(%Prepared{
        plan_id: plan_id,
        clock_session: clock_session,
        phase_run_id: phase_run_id,
        tier: tier
      }) do
    %{
      "plan_id" => plan_id,
      "clock_session" => clock_session,
      "phase_run_id" => phase_run_id,
      "tier" => Atom.to_string(tier)
    }
  end

  @doc "Decode the stored preparation result of one tier run."
  @spec decode_prepared(term()) :: {:ok, Prepared.t()} | :error
  def decode_prepared(
        %{
          "plan_id" => plan_id,
          "clock_session" => clock_session,
          "phase_run_id" => phase_run_id,
          "tier" => tier_name
        } = params
      )
      when is_binary(plan_id) and is_binary(clock_session) and byte_size(clock_session) > 0 and
             is_binary(phase_run_id) do
    with true <- exact_keys?(params, @prepared_keys),
         {:ok, tier} <- Map.fetch(@tier_names, tier_name),
         {:ok, ^plan_id} <- Ecto.UUID.cast(plan_id),
         {:ok, ^phase_run_id} <- Ecto.UUID.cast(phase_run_id) do
      {:ok,
       %Prepared{
         plan_id: plan_id,
         clock_session: clock_session,
         phase_run_id: phase_run_id,
         tier: tier
       }}
    else
      _invalid -> :error
    end
  end

  def decode_prepared(_params), do: :error

  @doc "Encode the created item batch as the mapped task parameters."
  @spec item_params([CollectionItem.t()]) :: [%{required(String.t()) => Ecto.UUID.t()}]
  def item_params(items), do: Enum.map(items, &%{"collection_item_id" => &1.id})

  @doc "Return the collection item of one mapped effect task."
  @spec run_item(term(), pos_integer()) :: {:ok, CollectionItem.t()} | {:error, term()}
  def run_item(item_id, run_id) do
    with {:ok, item} <- collection_item(item_id),
         {:ok, phase_run} <- stored_phase_run(item.study_phase_run_id),
         :ok <- ActionBoundary.expect_run_id(phase_run, run_id, @foreign_run_failure) do
      {:ok, item}
    end
  end

  @doc "Mark the start of one measured stage of one replica."
  @spec mark_start(binary(), 0..4, :plan_start | :simulation_start) ::
          {:ok, nil} | {:error, term()}
  def mark_start(clock_session, position, boundary) do
    case mark(clock_session, position, boundary) do
      {:ok, nil} -> {:ok, nil}
      {:ok, %Timing.Replica{}} -> tagged(:unexpected_start_mark, @timing_failure)
      {:error, _cause} = failure -> failure
    end
  end

  @doc "Mark the end of one measured replica and return its measured durations."
  @spec mark_replica(binary(), 0..4) :: {:ok, Timing.Replica.t()} | {:error, term()}
  def mark_replica(clock_session, position) do
    case mark(clock_session, position, :replica_end) do
      {:ok, %Timing.Replica{}} = success -> success
      {:ok, nil} -> tagged(:missing_replica_mark, @timing_failure)
      {:error, _cause} = failure -> failure
    end
  end

  @doc "Encode the measured durations of one replica as JSON-safe task parameters."
  @spec replica_params(0..4, Timing.Replica.t()) :: %{required(String.t()) => integer()}
  def replica_params(position, %Timing.Replica{} = replica) do
    %{
      "replica_position" => position,
      "plan_selection_us" => replica.plan_selection_us,
      "simulation_us" => replica.simulation_us,
      "total_us" => replica.total_us
    }
  end

  @doc "Decode the stored receipt of one completed replica."
  @spec decode_replica(term()) :: {:ok, {0..4, Timing.Replica.t()}} | :error
  def decode_replica(
        %{
          "replica_position" => position,
          "plan_selection_us" => plan_selection_us,
          "simulation_us" => simulation_us,
          "total_us" => total_us
        } = params
      )
      when position in 0..4 and is_integer(plan_selection_us) and plan_selection_us >= 0 and
             is_integer(simulation_us) and simulation_us >= 0 and is_integer(total_us) and
             total_us >= 0 do
    if exact_keys?(params, @replica_keys) and total_us == plan_selection_us + simulation_us do
      {:ok,
       {position,
        %Timing.Replica{
          plan_selection_us: plan_selection_us,
          simulation_us: simulation_us,
          total_us: total_us
        }}}
    else
      :error
    end
  end

  def decode_replica(_params), do: :error

  @doc "Return the stored receipt of one completed replica of the acting run."
  @spec stored_receipt(pos_integer(), 0..4) :: {:ok, term()} | {:error, term()}
  def stored_receipt(run_id, position), do: stored_task(replica_task(position), run_id)

  @doc "Return the Gust task name of one completed replica."
  @spec replica_task(0..4) :: String.t()
  def replica_task(position), do: "complete_replica_#{position}"

  @doc "Log and return one tagged permanent failure."
  @spec tagged(term(), String.t()) :: {:error, term()}
  def tagged(cause, message) do
    Logger.error(message, cause: inspect(cause))
    {:error, cause}
  end

  @spec input(map()) :: {:ok, TierContract.Input.t()} | {:error, :invalid_input}
  def input(params) do
    case TierContract.decode_input(params) do
      {:ok, input} -> {:ok, input}
      :error -> tagged(:invalid_input, @context_failure)
    end
  end

  @spec phase_run_context(Ecto.UUID.t()) :: {:ok, context()} | {:error, term()}
  def phase_run_context(phase_run_id) do
    ActionBoundary.phase_run_context(@context_failure, phase_run_id)
  end

  @spec logged(String.t(), {:ok, value} | {:error, term()}) :: {:ok, value} | {:error, term()}
        when value: var
  def logged(message, result), do: ActionBoundary.logged(message, result)

  @spec logged_status(String.t(), :ok | {:error, term()}) :: :ok | {:error, term()}
  def logged_status(message, result), do: ActionBoundary.logged_status(message, result)

  # --- binding internals --------------------------------------------------

  @spec expect_final_collection(Persistence.Phase.t()) :: :ok | {:error, :foreign_phase}
  defp expect_final_collection(%{phase: :final_collection}), do: :ok

  defp expect_final_collection(%{phase: phase}) do
    Logger.error(@foreign_phase_failure, phase: inspect(phase))
    {:error, :foreign_phase}
  end

  # The tier row is canonical when the stored row is the only row of its phase
  # and key. A run input that names another row of the same key is foreign.
  @spec expect_canonical(Persistence.Phase.t(), PhaseRun.t()) :: :ok | {:error, :not_canonical}
  defp expect_canonical(phase, %PhaseRun{id: phase_run_id, run_key: run_key}) do
    case Persistence.fetch_phase_run(phase.id, run_key) do
      {:ok, %PhaseRun{id: ^phase_run_id}} ->
        :ok

      _foreign_or_missing ->
        Logger.error(@not_canonical_failure, phase_run_id: phase_run_id)
        {:error, :not_canonical}
    end
  end

  @spec expect_prepared(Prepared.t(), context()) :: :ok | {:error, :foreign_prepare}
  defp expect_prepared(%Prepared{} = prepared, %{phase_run: phase_run}) do
    if prepared.phase_run_id == phase_run.id and prepared.tier == phase_run.run_key do
      :ok
    else
      Logger.error(@foreign_prepare_failure, phase_run_id: phase_run.id)
      {:error, :foreign_prepare}
    end
  end

  @spec stored_phase_run(Ecto.UUID.t()) :: {:ok, PhaseRun.t()} | {:error, term()}
  defp stored_phase_run(phase_run_id) do
    case phase_run_context(phase_run_id) do
      {:ok, context} -> {:ok, context.phase_run}
      {:error, _cause} = failure -> failure
    end
  end

  @spec collection_item(term()) :: {:ok, CollectionItem.t()} | {:error, term()}
  defp collection_item(item_id) do
    logged(@context_failure, Persistence.Collection.fetch_collection_item(item_id))
  end

  @spec mark(binary(), 0..4, atom()) :: {:ok, Timing.Replica.t() | nil} | {:error, term()}
  defp mark(clock_session, position, boundary) do
    logged(@timing_failure, FinalTiming.mark(clock_session, position, boundary))
  end

  # --- stored task results -------------------------------------------------

  # Gust starts a task again on retry and keeps one row per task name, so one
  # succeeded row is the complete stored result of that task.
  @spec stored_task(String.t(), pos_integer()) :: {:ok, term()} | {:error, term()}
  defp stored_task(name, run_id) do
    case Flows.get_tasks_by_name(name, run_id) do
      [%Task{status: :succeeded, result: result}] -> {:ok, result}
      _missing_or_repeated -> tagged({:task_result, name}, @task_failure)
    end
  end

  @spec decoded_prepared(term()) :: {:ok, Prepared.t()} | {:error, :invalid_prepare}
  defp decoded_prepared(result) do
    case decode_prepared(result) do
      {:ok, prepared} -> {:ok, prepared}
      :error -> tagged(:invalid_prepare, @prepare_failure)
    end
  end

  @spec exact_keys?(map(), [String.t()]) :: boolean()
  defp exact_keys?(params, expected_keys), do: Enum.sort(Map.keys(params)) == expected_keys

  @spec configured_environment_label() :: String.t() | nil
  defp configured_environment_label do
    Application.get_env(:network_defense, :measured_environment_revision)
  end
end
