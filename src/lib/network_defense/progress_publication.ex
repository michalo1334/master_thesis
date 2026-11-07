defmodule NetworkDefense.ProgressPublication do
  @moduledoc false

  # UI signals cannot change effect completion or callback control outcomes.
  def broadcast(server, topic, {kind, payload}) do
    metadata = Logger.metadata()

    payload =
      Map.merge(payload, %{
        observation_task_id: metadata[:task_id],
        observation_attempt: metadata[:attempt],
        observation_sequence: System.unique_integer([:monotonic, :positive])
      })

    Phoenix.PubSub.broadcast(server, topic, {kind, payload})
    :ok
  rescue
    _exception -> :ok
  catch
    :exit, _reason -> :ok
  end
end
