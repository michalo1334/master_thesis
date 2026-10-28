defmodule NetworkDefense.Evaluation.Study.Pipeline.GustNotifier do
  @moduledoc false

  @registry NetworkDefense.Evaluation.Study.Pipeline.GustWaiterRegistry

  @spec notify(integer()) :: :ok
  def notify(run_id) when is_integer(run_id) do
    Registry.dispatch(@registry, run_id, fn entries ->
      Enum.each(entries, fn {pid, _value} ->
        send(pid, {:gust_run_finished, run_id})
      end)
    end)

    :ok
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  def notify(_invalid_run_id), do: :ok
end
