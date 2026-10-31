defmodule Mix.Tasks.Study.Create do
  @moduledoc """
  Freezes one study revision from a YAML definition file.

      mix study.create <file>

  The command validates and resolves the definition through
  `NetworkDefense.Evaluation2.Study.create_revision/1`, then prints the declared
  study identifier and revision number. One frozen revision supports several
  executions, so this import runs once per definition.

  The command starts the application with the non-executing Gust role, because
  revision creation never dispatches work.
  """

  use Mix.Task

  @shortdoc "Freezes one study revision from a YAML file"
  @requirements ["app.config"]

  alias Mix.Study.Command
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Revision

  @usage "Usage: mix study.create <file>"
  @document_limit 1_048_576

  @impl Mix.Task
  def run(args) do
    case args do
      [path] -> create(path)
      _invalid -> Mix.raise(@usage)
    end
  end

  defp create(path) do
    document = read!(path)
    Command.start!(:inspect)

    case Study.create_revision(document) do
      {:ok, %Revision{} = revision} -> Command.print(revision_lines(revision))
      {:error, error} -> Command.reject!(:create, error)
    end
  end

  defp revision_lines(revision) do
    ["Study: #{revision.study_id}", "Revision: #{revision.revision}"]
  end

  defp read!(path) do
    with {:ok, %File.Stat{size: size}} when size <= @document_limit <- File.stat(path),
         {:ok, document} <- File.read(path) do
      document
    else
      {:ok, %File.Stat{}} ->
        Mix.raise("The definition file exceeds the 1 MiB limit.")

      {:error, reason} ->
        Mix.raise("Cannot read #{path}: #{:file.format_error(reason)}")
    end
  end
end
