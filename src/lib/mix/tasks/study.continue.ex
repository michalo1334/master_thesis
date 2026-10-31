defmodule Mix.Tasks.Study.Continue do
  @moduledoc """
  Continues one study execution to its next supported boundary.

      mix study.continue <execution-id>

  The command waits indefinitely through
  `NetworkDefense.Evaluation2.Study.continue/1` and prints the refreshed status.
  It grants no Final approval, and an interrupted command VM stops its workers
  and clock, so the wait is not a safe way to detach measured work.

  The application starts with an execution-capable Gust role.
  """

  use Mix.Task

  @shortdoc "Continues one study execution to its next boundary"
  @requirements ["app.config"]

  alias Mix.Study.Command
  alias NetworkDefense.Evaluation2.Study

  @usage "Usage: mix study.continue <execution-id>"

  @impl Mix.Task
  def run(args) do
    case args do
      [execution_id] -> continue(execution_id)
      _invalid -> Mix.raise(@usage)
    end
  end

  defp continue(execution_id) do
    Command.start!(:execute)

    case Study.continue(execution_id) do
      {:ok, status} ->
        Command.print(Command.status_lines(status))
        Command.require_boundary!(:continue, status, [:awaiting_final, :succeeded, :cancelled])

      {:error, error} ->
        Command.reject!(:continue, error)
    end
  end
end
