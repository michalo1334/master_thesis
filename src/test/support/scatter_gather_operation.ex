defmodule NetworkDefense.TestScatterGatherOperation do
  @moduledoc false

  @behaviour NetworkDefense.Compute.ScatterGather

  @impl true
  def scatter(input), do: input.partitions

  @impl true
  def execute(fetch_partition) do
    case fetch_partition.() do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        {:error, reason}

      {:exit, reason} ->
        exit(reason)

      {:sleep, milliseconds, value} ->
        Process.sleep(milliseconds)
        {:ok, value}

      {:notify, pid, value} ->
        send(pid, {:partition_started, self()})

        receive do
          :continue -> :ok
        end

        {:ok, value}
    end
  end

  @impl true
  def gather(results, input, _stats) do
    send(input.test_pid, {:gathered, results})
    input.gather_result
  end
end
