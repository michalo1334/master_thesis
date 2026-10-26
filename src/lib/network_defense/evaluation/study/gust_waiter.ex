defmodule NetworkDefense.Evaluation.Study.GustWaiter do
  @moduledoc false

  @registry NetworkDefense.Evaluation.Study.GustWaiterRegistry

  @spec await(integer(), timeout()) ::
          {:ok, :succeeded} | {:error, :failed | :not_found | :timeout | :unavailable}
  def await(run_id, timeout \\ :infinity)
      when is_integer(run_id) and
             (timeout == :infinity or (is_integer(timeout) and timeout >= 0)) do
    caller = self()
    reference = make_ref()
    deadline = deadline(timeout)

    {waiter, waiter_monitor} =
      spawn_monitor(fn -> wait(caller, reference, run_id, deadline) end)

    receive do
      {^reference, result} ->
        send(waiter, {:gust_waiter_ack, reference})
        await_waiter_exit(waiter, waiter_monitor, result)

      {:DOWN, ^waiter_monitor, :process, ^waiter, reason} ->
        exit({:gust_waiter_failed, reason})
    end
  end

  defp wait(caller, reference, run_id, deadline) do
    caller_monitor = Process.monitor(caller)

    case register(run_id) do
      :ok ->
        try do
          case persisted_result(run_id) do
            :continue ->
              wait_for_notification(caller, caller_monitor, reference, run_id, deadline)

            result ->
              deliver_result(caller, caller_monitor, reference, result)
          end
        after
          unregister(run_id)
        end

      {:error, :unavailable} = error ->
        deliver_result(caller, caller_monitor, reference, error)
    end
  end

  defp register(run_id) do
    case Registry.register(@registry, run_id, nil) do
      {:ok, _owner} -> :ok
      {:error, _reason} -> {:error, :unavailable}
    end
  rescue
    ArgumentError -> {:error, :unavailable}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp unregister(run_id) do
    Registry.unregister(@registry, run_id)
  rescue
    ArgumentError -> :ok
  catch
    :exit, _reason -> :ok
  end

  defp wait_for_notification(caller, caller_monitor, reference, run_id, deadline) do
    case remaining(deadline) do
      0 ->
        deliver_result(caller, caller_monitor, reference, {:error, :timeout})

      timeout ->
        receive do
          {:gust_run_finished, ^run_id} ->
            case persisted_result(run_id) do
              :continue ->
                wait_for_notification(caller, caller_monitor, reference, run_id, deadline)

              result ->
                deliver_result(caller, caller_monitor, reference, result)
            end

          {:DOWN, ^caller_monitor, :process, ^caller, _reason} ->
            :ok
        after
          timeout ->
            deliver_result(caller, caller_monitor, reference, {:error, :timeout})
        end
    end
  end

  defp persisted_result(run_id) do
    case Gust.Repo.get(Gust.Flows.Run, run_id) do
      nil -> {:error, :not_found}
      %{status: :succeeded} -> {:ok, :succeeded}
      %{status: :failed} -> {:error, :failed}
      _active -> :continue
    end
  end

  defp deliver_result(caller, caller_monitor, reference, result) do
    send(caller, {reference, result})

    receive do
      {:gust_waiter_ack, ^reference} -> :ok
      {:DOWN, ^caller_monitor, :process, ^caller, _reason} -> :ok
    end
  end

  defp await_waiter_exit(waiter, waiter_monitor, result) do
    receive do
      {:DOWN, ^waiter_monitor, :process, ^waiter, :normal} -> result
      {:DOWN, ^waiter_monitor, :process, ^waiter, reason} -> exit({:gust_waiter_failed, reason})
    end
  end

  defp deadline(:infinity), do: :infinity
  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp remaining(:infinity), do: :infinity

  defp remaining(deadline) do
    max(deadline - System.monotonic_time(:millisecond), 0)
  end
end
