defmodule NetworkDefense.Evaluation2.Study.Workflow.RunMonitor do
  @moduledoc """
  Wait-only monitor of one linked Gust run and its study execution.

  The monitor answers one question: is it still useful for the caller to wait?
  It never provisions, dispatches, accepts, or cancels work. Lifecycle
  transitions stay with `Study.Persistence`, and Gust mechanics stay with
  `Study.Workflow`.

  ## Contract

      await(gust_run_id, execution_id, timeout \\ :infinity)

      => {:ok, :terminal}      the linked Gust run is `succeeded` or `failed`
       | {:ok, :cancelled}     the durable execution is `cancelled` or `failed`
       | :timeout              the caller's elapsed bound ran out
       | {:error, Study.Error} a linked record is missing or storage is down

  `:cancelled` names one condition: the durable execution no longer accepts a
  completion of this run. Both `cancelled` and `failed` executions report it,
  because a failed execution rejects late acceptance in the same way. The
  fenced value wins over a Gust terminal status, so a cancelled execution that
  receives a late valid completion still ends the wait as `:cancelled`.

  The caller re-reads `Status` after every outcome. `:terminal` states that a
  terminal run status exists; it makes no claim about completion proof.

  ## Waiting rules

  Each wait polls the durable execution state and the Gust run status once per
  bounded interval, so a cancellation committed by another VM ends a blocked
  continuation without a local notification. A poll interval is short enough
  for operator feedback and long enough to keep two indexed reads per wait
  cheap.

  A finite timeout uses monotonic time. It bounds the caller's wait only, so a
  timeout never stops, fails, or cancels the run. The first probe runs before
  the bound is applied, so an already-terminal run answers without waiting.

  The monitor links each wait to its caller and removes the wait when the
  caller exits, so an abandoned continuation leaves no entry behind. One
  process serves every wait, and its polls run one after another.

  A missing record and an unavailable store end the wait with a bounded error
  instead of retrying, because the caller can still re-read `Status` and decide.
  """

  use GenServer

  import Ecto.Query

  alias Gust.Flows.Run
  alias Gust.Repo, as: GustRepo
  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Persistence.Execution
  alias NetworkDefense.Repo

  @name __MODULE__
  @default_poll_interval_ms 100
  @terminal_run_statuses [:succeeded, :failed]
  @fenced_execution_states [:cancelled, :failed]

  @typedoc "Outcome of one wait."
  @type outcome :: {:ok, :terminal} | {:ok, :cancelled} | :timeout | {:error, Error.t()}

  @typedoc "Wait identity: the linked Gust run and its durable execution."
  @type key :: {pos_integer(), Ecto.UUID.t()}

  defstruct waits: %{}, poll_interval: @default_poll_interval_ms

  @type t :: %__MODULE__{waits: %{key() => map()}, poll_interval: pos_integer()}

  @doc """
  Wait until the linked run or the durable execution reaches the end of the
  wait, or until the elapsed bound runs out.
  """
  @spec await(pos_integer(), Ecto.UUID.t(), timeout()) :: outcome()
  def await(gust_run_id, execution_id, timeout \\ :infinity)
      when is_integer(gust_run_id) and gust_run_id > 0 and is_binary(execution_id) and
             (timeout == :infinity or (is_integer(timeout) and timeout >= 0)) do
    message = {:await, gust_run_id, execution_id, deadline(timeout)}

    try do
      GenServer.call(@name, message, :infinity)
    catch
      :exit, _reason -> {:error, monitor_unavailable_error()}
    end
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @impl true
  def init(opts) do
    {:ok,
     %__MODULE__{poll_interval: Keyword.get(opts, :poll_interval, @default_poll_interval_ms)}}
  end

  @impl true
  def handle_call({:await, gust_run_id, execution_id, deadline_ms}, from, state) do
    key = {gust_run_id, execution_id}

    case probe(gust_run_id, execution_id) do
      :wait -> {:noreply, register(state, key, from, deadline_ms)}
      {:error, error} -> {:reply, {:error, error}, state}
      classification -> {:reply, {:ok, classification}, state}
    end
  end

  @impl true
  def handle_info({:poll, key}, state) do
    case Map.fetch(state.waits, key) do
      :error -> {:noreply, state}
      {:ok, wait} -> {:noreply, poll_wait(state, key, wait)}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    {:noreply, drop_caller(state, monitor)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # --- wait bookkeeping ---------------------------------------------------

  defp register(state, key, from, deadline_ms) do
    if expired?(deadline_ms) do
      GenServer.reply(from, :timeout)
      state
    else
      wait =
        state.waits
        |> Map.fetch(key)
        |> existing_or_new_wait(state, key)
        |> add_caller(from, deadline_ms)

      %{state | waits: Map.put(state.waits, key, wait)}
    end
  end

  defp existing_or_new_wait({:ok, wait}, _state, _key), do: wait
  defp existing_or_new_wait(:error, state, key), do: new_wait(state, key)

  defp new_wait(state, key) do
    %{callers: %{}, timer: Process.send_after(self(), {:poll, key}, state.poll_interval)}
  end

  defp add_caller(wait, from, deadline_ms) do
    monitor = Process.monitor(elem(from, 0))
    caller = %{from: from, deadline: deadline_ms}

    %{wait | callers: Map.put(wait.callers, monitor, caller)}
  end

  defp poll_wait(state, {gust_run_id, execution_id} = key, wait) do
    case probe(gust_run_id, execution_id) do
      :wait -> expire(state, key, wait)
      {:error, error} -> finish(state, key, {:error, error})
      classification -> finish(state, key, {:ok, classification})
    end
  end

  defp finish(state, key, result) do
    case Map.pop(state.waits, key) do
      {nil, _waits} ->
        state

      {wait, waits} ->
        Process.cancel_timer(wait.timer)
        reply_all(wait, result)
        %{state | waits: waits}
    end
  end

  defp expire(state, key, wait) do
    now = System.monotonic_time(:millisecond)

    {expired, waiting} =
      Enum.split_with(wait.callers, fn {_monitor, caller} -> expired?(caller.deadline, now) end)

    Enum.each(expired, fn {monitor, caller} -> reply(monitor, caller, :timeout) end)

    case waiting do
      [] ->
        Process.cancel_timer(wait.timer)
        %{state | waits: Map.delete(state.waits, key)}

      callers ->
        wait = %{wait | callers: Map.new(callers), timer: next_poll(state, key)}
        %{state | waits: Map.put(state.waits, key, wait)}
    end
  end

  defp next_poll(state, key) do
    Process.send_after(self(), {:poll, key}, state.poll_interval)
  end

  defp reply_all(wait, result) do
    Enum.each(wait.callers, fn {monitor, caller} -> reply(monitor, caller, result) end)
  end

  defp reply(monitor, caller, result) do
    Process.demonitor(monitor, [:flush])
    GenServer.reply(caller.from, result)
  end

  defp drop_caller(state, monitor) do
    waits =
      Enum.reduce(state.waits, %{}, fn {key, wait}, acc ->
        case Map.pop(wait.callers, monitor) do
          {nil, _callers} ->
            Map.put(acc, key, wait)

          {_caller, callers} when map_size(callers) == 0 ->
            Process.cancel_timer(wait.timer)
            acc

          {_caller, callers} ->
            Map.put(acc, key, %{wait | callers: callers})
        end
      end)

    %{state | waits: waits}
  end

  defp deadline(:infinity), do: :infinity

  defp deadline(timeout) when is_integer(timeout),
    do: System.monotonic_time(:millisecond) + timeout

  defp expired?(:infinity), do: false
  defp expired?(deadline_ms), do: expired?(deadline_ms, System.monotonic_time(:millisecond))

  defp expired?(:infinity, _now), do: false
  defp expired?(deadline_ms, now), do: now >= deadline_ms

  # --- durable probes -----------------------------------------------------

  defp probe(gust_run_id, execution_id) do
    with {:ok, execution_state} <- execution_state(execution_id),
         {:ok, run_status} <- run_status(gust_run_id) do
      classify(execution_state, run_status)
    end
  end

  defp classify(execution_state, _run_status)
       when execution_state in @fenced_execution_states,
       do: :cancelled

  defp classify(:succeeded, _run_status), do: :terminal

  defp classify(_execution_state, run_status) when run_status in @terminal_run_statuses,
    do: :terminal

  defp classify(_execution_state, _run_status), do: :wait

  defp execution_state(execution_id) do
    case Ecto.UUID.cast(execution_id) do
      {:ok, execution_uuid} -> contained(fn -> stored_execution_state(execution_uuid) end)
      :error -> {:error, missing_execution_error()}
    end
  end

  defp stored_execution_state(execution_uuid) do
    case Repo.one(from e in Execution, where: e.id == ^execution_uuid, select: e.state) do
      nil -> {:error, missing_execution_error()}
      state -> {:ok, state}
    end
  end

  defp run_status(gust_run_id) do
    contained(fn -> stored_run_status(gust_run_id) end)
  end

  defp stored_run_status(gust_run_id) do
    case GustRepo.one(from r in Run, where: r.id == ^gust_run_id, select: r.status) do
      nil -> {:error, missing_run_error()}
      status -> {:ok, status}
    end
  end

  # Storage exceptions keep the same containment as the persistence boundary, so
  # one failed poll reports a bounded error instead of stopping the monitor and
  # every other waiting caller with it.
  defp contained(fun) do
    fun.()
  rescue
    _exception in [Postgrex.Error, DBConnection.ConnectionError, DBConnection.OwnershipError] ->
      {:error, storage_error()}
  end

  defp error(category, code, message) do
    %Error{
      category: category,
      issues: [%Error.Issue{code: code, path: [], message: message}]
    }
  end

  defp missing_execution_error do
    error(:validation_failed, "execution_not_found", "The study execution does not exist.")
  end

  defp missing_run_error do
    error(:unavailable, "run_not_found", "The linked Gust run does not exist.")
  end

  defp storage_error do
    error(:unavailable, "storage_unavailable", "The study storage is unavailable.")
  end

  defp monitor_unavailable_error do
    error(:unavailable, "monitor_unavailable", "The run monitor is not available.")
  end
end
