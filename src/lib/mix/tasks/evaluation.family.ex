defmodule Mix.Tasks.Evaluation.Family do
  @moduledoc """
  Runs a declared primary comparison family through the Gust workflow.

  Starts only Gust in console role, using one database connection. The command
  prints one row per comparison in declared order and reads the result through
  the public family boundary.

  The output is synthetic-prototype evidence only. It is not Pilot or Final
  evidence.
  """

  use Mix.Task

  @shortdoc "Runs the synthetic complete-family Holm prototype"
  @requirements ["app.config"]

  alias NetworkDefense.Evaluation.Family.{Console, ResultFormatter}
  alias NetworkDefense.Evaluations

  @wait_timeout 240_000
  @request_limit 1_048_576

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: [fixture: :string])

    if positional != [] or invalid != [] do
      Mix.raise("Usage: mix evaluation.family --fixture <known-fixture>")
    end

    fixture_name = Keyword.get(options, :fixture, "holm-small")
    fixture_path = Console.fixture_path!(fixture_name)
    :ok = Console.start!()
    request = load_fixture!(fixture_path)

    case Evaluations.submit_family(request) do
      {:ok, run_id} -> run_and_print(run_id)
      {:error, error} -> fail(ResultFormatter.public_rejection(error))
    end
  end

  defp run_and_print(run_id) do
    case Evaluations.await_family(run_id, @wait_timeout) do
      {:ok, :succeeded} ->
        case Evaluations.get_family_result(run_id) do
          {:ok, result} -> Mix.shell().info(ResultFormatter.success(run_id, result))
          {:error, error} -> fail(ResultFormatter.failure(run_id, "correct_family", error))
        end

      {:error, error} when is_struct(error) ->
        fail(ResultFormatter.failure(run_id, "family", error))

      {:error, reason} ->
        fail("Run: #{run_id}\nStatus: #{reason}\nStored result: none")
    end
  end

  defp load_fixture!(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= @request_limit ->
        path |> File.read!() |> Jason.decode!()

      {:ok, _stat} ->
        Mix.raise("Fixture exceeds the 1-MiB request limit.")

      {:error, reason} ->
        Mix.raise("Cannot read fixture: #{:file.format_error(reason)}")
    end
  end

  @spec fail(String.t()) :: no_return()
  defp fail(message) do
    Mix.shell().error(message)
    Mix.raise("family command failed")
  end
end
