defmodule NetworkDefenseWeb.StudyObserver do
  @moduledoc false
  use GenServer

  alias NetworkDefense.Evaluation2.Study.Progress
  alias NetworkDefenseWeb.StudyWire
  alias Phoenix.PubSub

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    execution_id = Keyword.fetch!(opts, :execution_id)
    Process.monitor(owner)
    PubSub.subscribe(NetworkDefense.PubSub, Progress.topic(execution_id))

    PubSub.subscribe(
      NetworkDefense.PubSub,
      NetworkDefense.Optimizations.optimization_events_topic()
    )

    PubSub.subscribe(
      NetworkDefense.PubSub,
      NetworkDefense.Simulations.simulation_events_topic()
    )

    state = %{
      owner: owner,
      execution_id: execution_id,
      document_id: Keyword.fetch!(opts, :document_id),
      watch_id: Keyword.fetch!(opts, :watch_id),
      sequence: 0,
      live: %{},
      runs: MapSet.new(),
      items: MapSet.new(),
      timer: nil
    }

    {:ok, refresh(state)}
  end

  @impl true
  def handle_info({:refresh, token}, %{timer: {_ref, token, _due}} = state),
    do: {:noreply, refresh(%{state | timer: nil})}

  def handle_info({:refresh, _stale}, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, owner, _reason}, %{owner: owner} = state),
    do: {:stop, :normal, state}

  def handle_info({kind, payload}, state)
      when kind in [:optimization_progress, :simulation_progress] do
    state =
      case Progress.correlation(payload) do
        {:ok, item, stage} ->
          if MapSet.member?(state.items, item) do
            %{state | live: record(state.live, item, stage, payload)}
          else
            state
          end

        :ignore ->
          state
      end

    {:noreply, schedule(state, 150)}
  end

  def handle_info({:study_changed, _id}, state), do: {:noreply, refresh(state)}
  def handle_info({:dag, :run_status, _payload}, state), do: {:noreply, schedule(state, 100)}
  def handle_info(_message, state), do: {:noreply, schedule(state, 150)}

  @doc false
  def record(live, item, stage, payload) do
    key = {item, stage}
    previous = Map.get(live, key)

    older? =
      previous && previous[:observation_task_id] == payload[:observation_task_id] &&
        {previous[:observation_attempt] || 0, previous[:observation_sequence] || 0} >=
          {payload[:observation_attempt] || 0, payload[:observation_sequence] || 0}

    if older?, do: live, else: Map.put(live, key, payload)
  end

  defp refresh(state) do
    cancel_timer(state.timer)
    state = subscriptions(%{state | timer: nil})

    case Progress.snapshot(state.execution_id, state.live) do
      {:ok, snapshot} ->
        sequence = state.sequence + 1

        event = %{
          document_id: state.document_id,
          execution_id: state.execution_id,
          watch_id: state.watch_id,
          sequence: sequence,
          progress: StudyWire.wire(snapshot),
          status: StudyWire.wire(snapshot.status)
        }

        send(state.owner, {:study_observed, event})
        schedule(%{state | sequence: sequence}, 1_000)

      {:error, _error} ->
        schedule(state, 2_000)
    end
  end

  defp subscriptions(state) do
    runs =
      case Progress.run_ids(state.execution_id) do
        {:ok, ids} -> MapSet.new(ids)
        _ -> state.runs
      end

    Enum.each(MapSet.difference(runs, state.runs), &Gust.PubSub.subscribe_run/1)

    Enum.each(MapSet.difference(state.runs, runs), fn id ->
      PubSub.unsubscribe(Gust.PubSub, "dag:run:#{id}")
    end)

    items =
      case Progress.item_ids(state.execution_id) do
        {:ok, ids} -> MapSet.new(ids)
        _ -> state.items
      end

    live = Map.filter(state.live, fn {{id, _stage}, _value} -> MapSet.member?(items, id) end)
    %{state | runs: runs, items: items, live: live}
  end

  defp schedule(state, delay) do
    due = System.monotonic_time(:millisecond) + delay

    case state.timer do
      {_ref, _token, existing} when existing <= due ->
        state

      previous ->
        cancel_timer(previous)
        token = make_ref()
        %{state | timer: {Process.send_after(self(), {:refresh, token}, delay), token, due}}
    end
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer({ref, _token, _due}), do: Process.cancel_timer(ref)
end
