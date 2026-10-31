defmodule Mix.Tasks.Study.Result do
  @moduledoc """
  Prints the stored result of one successful study execution.

      mix study.result <execution-id>

  The result joins the accepted Pilot history with the corrected Final family and
  the measured timing. The command reads through
  `NetworkDefense.Evaluation2.Study.result/1`, so the application starts with the
  non-executing Gust role. A read before success returns a bounded error.
  """

  use Mix.Task

  @shortdoc "Prints the stored result of one successful study execution"
  @requirements ["app.config"]

  alias Mix.Study.Command
  alias NetworkDefense.Evaluation2.Study

  @usage "Usage: mix study.result <execution-id>"

  @impl Mix.Task
  def run(args) do
    case args do
      [execution_id] -> result(execution_id)
      _invalid -> Mix.raise(@usage)
    end
  end

  defp result(execution_id) do
    Command.start!(:inspect)

    case Study.result(execution_id) do
      {:ok, result} -> Command.print(Command.result_lines(result))
      {:error, error} -> Command.reject!(:result, error)
    end
  end
end
