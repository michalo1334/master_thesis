defmodule Mix.Tasks.Study.Pilot do
  @moduledoc """
  Starts one Pilot execution of a frozen revision and waits for its decision.

      mix study.pilot <study-id> <revision>

  The command starts the execution through
  `NetworkDefense.Evaluation2.Study.start/1`, waits through `continue/1`, and
  prints the execution identifier and the complete Pilot report. It returns when
  the execution reaches `awaiting_final`, which is the approval boundary.

  One frozen revision supports several executions, so this command imports no
  definition. The application starts with an execution-capable Gust role.
  """

  use Mix.Task

  @shortdoc "Runs one Pilot execution to the approval boundary"
  @requirements ["app.config"]

  alias Mix.Study.Command
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Revision
  alias NetworkDefense.Evaluation2.Study.Status

  @usage "Usage: mix study.pilot <study-id> <revision>"

  @impl Mix.Task
  def run(args) do
    case args do
      [study_id, revision] -> pilot(study_id, revision)
      _invalid -> Mix.raise(@usage)
    end
  end

  defp pilot(study_id, revision_text) do
    revision = %Revision{study_id: study_id, revision: parse_revision!(revision_text)}
    Command.start!(:execute)

    execution_id = start!(revision)
    # The committed execution must remain reachable after a wait failure or interruption.
    Command.print(["Execution: #{execution_id}"])
    status = continue!(execution_id, :pilot)

    Command.print(Command.status_lines(status))
    Command.require_boundary!(:pilot, status, [:awaiting_final])

    report!(execution_id)
  end

  defp parse_revision!(text) do
    case Integer.parse(text) do
      {revision, ""} when revision > 0 -> revision
      _invalid -> Mix.raise(@usage)
    end
  end

  defp start!(revision) do
    case Study.start(revision) do
      {:ok, %Status{execution_id: execution_id}} -> execution_id
      {:error, error} -> Command.reject!(:pilot, error)
    end
  end

  defp continue!(execution_id, operation) do
    case Study.continue(execution_id) do
      {:ok, %Status{} = status} -> status
      {:error, error} -> Command.reject!(operation, error)
    end
  end

  defp report!(execution_id) do
    case Study.pilot_result(execution_id) do
      {:ok, report} -> Command.print(Command.pilot_report_lines(report))
      {:error, error} -> Command.reject!(:pilot, error)
    end
  end
end
