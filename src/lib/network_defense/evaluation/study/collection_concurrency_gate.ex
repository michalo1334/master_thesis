defmodule NetworkDefense.Evaluation.Study.CollectionConcurrencyGate do
  @moduledoc false
  use GenServer

  alias NetworkDefense.Evaluation.Study.CollectionLimits
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  @call_timeout 5_000

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      type: :worker
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @spec run((-> result)) ::
          result | {:error, NetworkDefense.Evaluation.Study.Contracts.StudyError.t()}
        when result: term()
  def run(fun) when is_function(fun, 0) do
    with {:ok, %CollectionLimits{max_gust_concurrency: limit}} <- CollectionLimits.fetch(),
         {:ok, server} <- limiter_server(),
         {:ok, token} <- acquire(server, limit) do
      try do
        fun.()
      after
        _release_result = safe_call(server, {:release, token})
      end
    end
  end

  defp limiter_server do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> {:error, StudyError.collection_workflow_failed()}
    end
  end

  defp acquire(server, limit) do
    {:ok, GenServer.call(server, {:acquire, limit}, @call_timeout)}
  catch
    :exit, _reason ->
      GenServer.cast(server, {:cancel_acquire, self()})
      {:error, StudyError.collection_workflow_failed()}
  end

  defp safe_call(server, message) do
    {:ok, GenServer.call(server, message, @call_timeout)}
  catch
    :exit, _reason -> {:error, StudyError.collection_workflow_failed()}
  end

  @impl true
  def init(:ok), do: {:ok, %{holders: %{}, waiters: []}}

  @impl true
  def handle_call({:acquire, limit}, from, state) do
    pid = elem(from, 0)
    monitor = Process.monitor(pid)

    if map_size(state.holders) < limit do
      {token, state} = add_holder(state, pid, monitor)
      {:reply, token, state}
    else
      {:noreply, %{state | waiters: state.waiters ++ [{from, limit, monitor}]}}
    end
  end

  def handle_call({:release, token}, _from, state) do
    state = release_holder(state, token)
    {:reply, :ok, grant_waiters(state)}
  end

  @impl true
  def handle_cast({:cancel_acquire, pid}, state) do
    {cancelled_holders, holders} =
      Enum.split_with(state.holders, fn {_token, {holder_pid, _monitor}} ->
        holder_pid == pid
      end)

    {cancelled_waiters, waiters} =
      Enum.split_with(state.waiters, fn {from, _limit, _monitor} -> elem(from, 0) == pid end)

    Enum.each(cancelled_holders, fn {_token, {_pid, monitor}} ->
      Process.demonitor(monitor, [:flush])
    end)

    Enum.each(cancelled_waiters, fn {_from, _limit, monitor} ->
      Process.demonitor(monitor, [:flush])
    end)

    state = %{state | holders: Map.new(holders), waiters: waiters}
    {:noreply, grant_waiters(state)}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    holders =
      state.holders
      |> Enum.reject(fn {_token, {_holder_pid, holder_monitor}} -> holder_monitor == monitor end)
      |> Map.new()

    waiters =
      Enum.reject(state.waiters, fn {_from, _limit, waiter_monitor} ->
        waiter_monitor == monitor
      end)

    {:noreply, grant_waiters(%{state | holders: holders, waiters: waiters})}
  end

  defp add_holder(state, pid, monitor) do
    token = make_ref()
    {token, put_in(state, [:holders, token], {pid, monitor})}
  end

  defp release_holder(state, token) do
    case Map.pop(state.holders, token) do
      {nil, _holders} ->
        state

      {{_pid, monitor}, holders} ->
        Process.demonitor(monitor, [:flush])
        %{state | holders: holders}
    end
  end

  defp grant_waiters(%{waiters: []} = state), do: state

  defp grant_waiters(state) do
    case Enum.split_while(state.waiters, fn {_from, limit, _monitor} ->
           map_size(state.holders) >= limit
         end) do
      {_blocked, []} ->
        state

      {blocked, [{from, _limit, monitor} | rest]} ->
        pid = elem(from, 0)
        {token, state} = add_holder(%{state | waiters: blocked ++ rest}, pid, monitor)
        GenServer.reply(from, token)
        grant_waiters(state)
    end
  end
end
