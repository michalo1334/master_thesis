defmodule NetworkDefense.LogEventHandler do
  @moduledoc false

  @behaviour :logger_handler

  @impl true
  def log(event, %{config: %{test_pid: test_pid}}) do
    send(test_pid, {:log_event, event})
    :ok
  end
end
