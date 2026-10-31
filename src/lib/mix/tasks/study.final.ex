defmodule Mix.Tasks.Study.Final do
  @moduledoc """
  Approves the Pilot outcome of one execution and waits for the Final result.

      mix study.final <execution-id> --recommended
      mix study.final <execution-id> --override-insufficient <candidate-id>

  Exactly one approval flag is required. `--recommended` accepts the declared
  recommendation. `--override-insufficient` selects one declared candidate after
  an insufficient Pilot decision, so the override is an explicit operator
  decision. A repeated or contradictory flag is a usage error, because an
  approval is one declared intent.

  The command approves through `NetworkDefense.Evaluation2.Study.resume/2`, waits
  through `continue/1`, and prints the stored result. The application starts with
  an execution-capable Gust role.
  """

  use Mix.Task

  @shortdoc "Approves one Pilot outcome and runs Final collection to its result"
  @requirements ["app.config"]

  alias Mix.Study.Command
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.Status

  @usage """
  Usage: mix study.final <execution-id> --recommended
         mix study.final <execution-id> --override-insufficient <candidate-id>
  """

  @switches [recommended: :boolean, override_insufficient: :string]

  @recommended_flags ["--recommended", "--no-recommended"]
  @override_flag "--override-insufficient"

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    case {positional, invalid, approval(options, args)} do
      {[execution_id], [], {:ok, approval}} -> final(execution_id, approval)
      _invalid -> Mix.raise(@usage)
    end
  end

  # The approval is one declared intent. OptionParser keeps the last value of a
  # repeated flag, so the raw arguments decide whether a flag was declared once.
  defp approval(options, args) do
    with :ok <- single_declaration(args, @recommended_flags),
         :ok <- single_declaration(args, [@override_flag]) do
      case {Keyword.get(options, :recommended), Keyword.get(options, :override_insufficient)} do
        {true, nil} ->
          {:ok, :recommended}

        {nil, candidate} when is_binary(candidate) and candidate != "" ->
          {:ok, {:override_insufficient, candidate}}

        _invalid ->
          :error
      end
    end
  end

  defp single_declaration(args, flags) do
    if Enum.count(args, &declared?(&1, flags)) <= 1, do: :ok, else: :error
  end

  defp declared?(argument, flags), do: Enum.any?(flags, &flag?(argument, &1))

  defp flag?(argument, flag), do: argument == flag or String.starts_with?(argument, flag <> "=")

  defp final(execution_id, approval) do
    Command.start!(:execute)

    resume!(execution_id, approval)
    status = continue!(execution_id)

    Command.print(Command.status_lines(status))
    Command.require_boundary!(:final, status, [:succeeded])

    result!(execution_id)
  end

  defp resume!(execution_id, approval) do
    case Study.resume(execution_id, approval) do
      {:ok, %Status{}} -> :ok
      {:error, error} -> Command.reject!(:final, error)
    end
  end

  defp continue!(execution_id) do
    case Study.continue(execution_id) do
      {:ok, %Status{} = status} -> status
      {:error, error} -> Command.reject!(:final, error)
    end
  end

  defp result!(execution_id) do
    case Study.result(execution_id) do
      {:ok, result} -> Command.print(Command.result_lines(result))
      {:error, error} -> Command.reject!(:final, error)
    end
  end
end
