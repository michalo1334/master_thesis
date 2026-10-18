defmodule Mix.Tasks.Evaluation.Compare do
  @moduledoc """
  Runs a versioned evaluation comparison through the Gust workflow.

  Starts only Gust in console role, using one database connection.
  """

  use Mix.Task

  @shortdoc "Runs the synthetic crossed-comparison prototype"
  @requirements ["app.config"]

  alias NetworkDefense.Evaluation.Comparison.{Console, ResultFormatter}
  alias NetworkDefense.Evaluations

  @wait_timeout 240_000

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: [fixture: :string])

    if positional != [] or invalid != [] do
      Mix.raise("Usage: mix evaluation.compare --fixture <known-fixture>")
    end

    fixture_name = Keyword.get(options, :fixture, "crossed-small")
    fixture_path = Console.fixture_path!(fixture_name)
    :ok = Console.start!()
    request = load_fixture!(fixture_path)

    case Evaluations.submit_comparison(request) do
      {:ok, run_id} -> run_and_print(run_id)
      {:error, error} -> fail(ResultFormatter.public_rejection(error))
    end
  end

  defp run_and_print(run_id) do
    case Evaluations.await_comparison(run_id, @wait_timeout) do
      {:ok, :succeeded} ->
        case Evaluations.get_comparison_result(run_id) do
          {:ok, statistics} -> Mix.shell().info(ResultFormatter.success(run_id, statistics))
          {:error, error} -> fail(ResultFormatter.failure(run_id, "compare", error))
        end

      {:error, error} when is_struct(error) ->
        fail(ResultFormatter.failure(run_id, "comparison", error))

      {:error, reason} ->
        fail("Run: #{run_id}\nStatus: #{reason}\nStored result: none")
    end
  end

  defp load_fixture!(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= 1_048_576 -> path |> File.read!() |> Jason.decode!()
      {:ok, _stat} -> Mix.raise("Fixture exceeds the 1-MiB request limit.")
      {:error, reason} -> Mix.raise("Cannot read fixture: #{:file.format_error(reason)}")
    end
  end

  @spec fail(String.t()) :: no_return()
  defp fail(message) do
    Mix.shell().error(message)
    Mix.raise("comparison command failed")
  end
end
