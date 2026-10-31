defmodule Mix.Tasks.Study.PilotResult do
  @moduledoc """
  Prints the complete Pilot report of one study execution.

      mix study.pilot_result <execution-id>

  The report names the accepted outcome, the fixed method and selection rule, and
  every declared candidate with its per comparison assessment. The command reads
  through `NetworkDefense.Evaluation2.Study.pilot_result/1`, so the application
  starts with the non-executing Gust role.
  """

  use Mix.Task

  @shortdoc "Prints the complete Pilot report of one study execution"
  @requirements ["app.config"]

  alias Mix.Study.Command
  alias NetworkDefense.Evaluation2.Study

  @usage "Usage: mix study.pilot_result <execution-id>"

  @impl Mix.Task
  def run(args) do
    case args do
      [execution_id] -> pilot_result(execution_id)
      _invalid -> Mix.raise(@usage)
    end
  end

  defp pilot_result(execution_id) do
    Command.start!(:inspect)

    case Study.pilot_result(execution_id) do
      {:ok, report} -> Command.print(Command.pilot_report_lines(report))
      {:error, error} -> Command.reject!(:pilot_result, error)
    end
  end
end
