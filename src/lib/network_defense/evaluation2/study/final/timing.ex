defmodule NetworkDefense.Evaluation2.Study.Final.Timing do
  @moduledoc """
  Application-owned monotonic clock for Final tier measurements.

  Sessions contain only transient readings. Gust stores completed durations.
  A marker can retry within its session. A lost session cannot resume readings.

  ```mermaid
  flowchart LR
      Plan[Plan start] --> Handoff[Plan complete and simulation start]
      Handoff --> End[Replica end]
      End --> Receipt[Persist completed duration triplet in Gust]
  ```

  The shared handoff marker partitions total elapsed time into plan selection
  and simulation. Queue, scheduling and retry delays inside those boundaries
  remain measured. Preparation before plan start and later analysis stay out.
  This service owns no lifecycle progression or acceptance. Workflow releases
  transient state only after proving durable canonical tier completion.
  """

  use GenServer

  alias NetworkDefense.Evaluation2.Study.Error
  alias NetworkDefense.Evaluation2.Study.Result.Timing, as: ResultTiming
  alias NetworkDefense.Evaluation2.Study.Result.Timing.Replica

  @doc "Start the application-owned clock before dispatch-capable Gust work."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Bind one transient clock session to a canonical tier PhaseRun."
  def begin_tier(phase_run_id, server \\ __MODULE__),
    do: call(server, {:begin_tier, phase_run_id})

  @doc "Record the next ordered boundary, or return its existing receipt on retry."
  def mark(session, position, boundary, server \\ __MODULE__),
    do: call(server, {:mark, session, position, boundary})

  # The caller releases a session only after proving its durable terminal result.
  @doc "Release transient state after canonical durable completion; do not release incomplete proof."
  def release(session, server \\ __MODULE__), do: call(server, {:release, session})

  @doc "Build the typed result timing from proven complete tier receipts."
  def summarize(tier_runs) do
    %ResultTiming{by_tier: Map.new(tier_runs, &{&1.tier, &1.timing})}
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:microsecond) end),
       sessions: %{},
       bindings: %{}
     }}
  end

  @impl true
  def handle_call({:begin_tier, phase_run_id}, _from, state) do
    case Map.fetch(state.bindings, phase_run_id) do
      {:ok, {:active, session}} ->
        {:reply, {:ok, session}, state}

      {:ok, :released} ->
        {:reply, failure("clock_session_released"), state}

      :error ->
        begin_session(phase_run_id, state)
    end
  end

  def handle_call({:mark, token, position, boundary}, _from, state) do
    case Map.fetch(state.sessions, token) do
      {:ok, session} ->
        marked(token, session, position, boundary, state)

      :error ->
        {:reply, failure("clock_session_lost"), state}
    end
  end

  def handle_call({:release, token}, _from, state) do
    case Map.pop(state.sessions, token) do
      {nil, _sessions} ->
        {:reply, :ok, state}

      {session, sessions} ->
        bindings = Map.put(state.bindings, session.phase_run_id, :released)
        {:reply, :ok, %{state | sessions: sessions, bindings: bindings}}
    end
  end

  defp begin_session(phase_run_id, state) do
    case Ecto.UUID.cast(phase_run_id) do
      {:ok, ^phase_run_id} ->
        token = Ecto.UUID.generate()

        session = %{
          phase_run_id: phase_run_id,
          next: {0, :plan_start},
          readings: %{},
          receipts: %{}
        }

        sessions = Map.put(state.sessions, token, session)
        bindings = Map.put(state.bindings, phase_run_id, {:active, token})
        {:reply, {:ok, token}, %{state | sessions: sessions, bindings: bindings}}

      _invalid ->
        {:reply, failure("invalid_clock_binding"), state}
    end
  end

  defp marked(token, session, position, boundary, state) do
    key = {position, boundary}

    case Map.fetch(session.receipts, key) do
      {:ok, receipt} ->
        {:reply, {:ok, receipt}, state}

      :error when session.next == key ->
        record_marker(token, session, key, state)

      :error ->
        {:reply, failure("invalid_clock_sequence"), state}
    end
  end

  defp record_marker(token, session, {position, boundary} = key, state) do
    reading = state.clock.()

    if is_integer(reading) and ordered?(session, reading) do
      readings = Map.put(session.readings, key, reading)
      receipt = receipt(readings, position, boundary)

      updated = %{
        session
        | readings: readings,
          receipts: Map.put(session.receipts, key, receipt),
          next: next_marker(position, boundary)
      }

      {:reply, {:ok, receipt}, %{state | sessions: Map.put(state.sessions, token, updated)}}
    else
      {:reply, failure("invalid_clock_reading"), state}
    end
  end

  defp ordered?(%{readings: readings}, reading) when map_size(readings) == 0,
    do: is_integer(reading)

  defp ordered?(%{readings: readings}, reading), do: reading >= Enum.max(Map.values(readings))

  defp next_marker(position, :plan_start), do: {position, :simulation_start}
  defp next_marker(position, :simulation_start), do: {position, :replica_end}
  defp next_marker(position, :replica_end) when position < 4, do: {position + 1, :plan_start}
  defp next_marker(4, :replica_end), do: :completed

  defp receipt(readings, position, :replica_end) do
    start = Map.fetch!(readings, {position, :plan_start})
    simulation = Map.fetch!(readings, {position, :simulation_start})
    finish = Map.fetch!(readings, {position, :replica_end})

    %Replica{
      plan_selection_us: simulation - start,
      simulation_us: finish - simulation,
      total_us: finish - start
    }
  end

  defp receipt(_readings, _position, _boundary), do: nil

  defp call(server, message) do
    GenServer.call(server, message)
  catch
    :exit, _reason -> failure("clock_session_lost")
  end

  defp failure(code) do
    {:error,
     %Error{
       category: :unavailable,
       issues: [
         %Error.Issue{
           code: code,
           path: [],
           message: "The Final clock session cannot complete this measurement."
         }
       ]
     }}
  end
end
