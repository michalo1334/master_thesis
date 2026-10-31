defmodule Mix.Tasks.Study.Status do
  @moduledoc """
  Prints the lifecycle status of one study execution.

      mix study.status <execution-id>

  The command reads through `NetworkDefense.Evaluation2.Study.status/1` and
  prints the state with the accepted Pilot outcome, the frozen selection, and a
  bounded failure when one exists. It dispatches no work, so the application
  starts with the non-executing Gust role.
  """

  use Mix.Task

  @shortdoc "Prints the lifecycle status of one study execution"
  @requirements ["app.config"]

  alias Mix.Study.Command
  alias NetworkDefense.Evaluation2.Study

  @usage "Usage: mix study.status <execution-id>"

  @impl Mix.Task
  def run(args) do
    case args do
      [execution_id] -> status(execution_id)
      _invalid -> Mix.raise(@usage)
    end
  end

  defp status(execution_id) do
    Command.start!(:inspect)

    case Study.status(execution_id) do
      {:ok, status} -> Command.print(Command.status_lines(status))
      {:error, error} -> Command.reject!(:status, error)
    end
  end
end
