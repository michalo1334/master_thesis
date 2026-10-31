defmodule Mix.Tasks.Study.Cancel do
  @moduledoc """
  Cancels one study execution that is not terminal.

      mix study.cancel <execution-id>

  Cancellation is a durable lifecycle event. The command commits it through
  `NetworkDefense.Evaluation2.Study.cancel/1`; the study then stops the linked
  Gust runs on a best-effort basis, and a late valid completion leaves the
  execution cancelled.

  The application starts with the non-executing Gust `console` role. The
  cancelling VM must claim no queued work of the target execution or of another
  study before the durable cancel commits. A blocked continuation observes the
  committed cancellation through persisted state, because its wait re-reads the
  execution row from any command VM.
  """

  use Mix.Task

  @shortdoc "Cancels one study execution that is not terminal"
  @requirements ["app.config"]

  alias Mix.Study.Command
  alias NetworkDefense.Evaluation2.Study

  @usage "Usage: mix study.cancel <execution-id>"

  @impl Mix.Task
  def run(args) do
    case args do
      [execution_id] -> cancel(execution_id)
      _invalid -> Mix.raise(@usage)
    end
  end

  defp cancel(execution_id) do
    Command.start!(:inspect)

    case Study.cancel(execution_id) do
      {:ok, status} -> Command.print(Command.status_lines(status))
      {:error, error} -> Command.reject!(:cancel, error)
    end
  end
end
