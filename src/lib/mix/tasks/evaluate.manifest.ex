defmodule Mix.Tasks.Evaluate.Manifest do
  use Mix.Task

  @shortdoc "Run a saved evaluation manifest"

  @moduledoc """
  Runs a saved manifest through the shared evaluation context.

      mix evaluate.manifest --manifest-id fixed-enterprise-v1
  """

  @requirements ["app.start"]
  @switches [manifest_id: :string]

  alias NetworkDefense.Evaluation

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    with :ok <- validate_options(positional, invalid, options[:manifest_id]),
         {:ok, evaluation_run} <- Evaluation.start(options[:manifest_id]),
         {:ok, completed_run} <- Evaluation.run(evaluation_run.id) do
      IO.puts(
        Jason.encode!(%{
          "evaluation_run_id" => completed_run.id,
          "manifest_id" => options[:manifest_id],
          "status" => completed_run.status
        })
      )
    else
      {:error, :not_found} -> Mix.raise("evaluation manifest not found")
      {:error, errors} when is_list(errors) -> Mix.raise(format_errors(errors))
      {:error, reason} when is_binary(reason) -> Mix.raise(reason)
      {:error, reason} -> Mix.raise("evaluation failed: #{inspect(reason)}")
    end
  end

  defp validate_options([], [], manifest_id) when is_binary(manifest_id), do: :ok

  defp validate_options([], [], _manifest_id),
    do: {:error, "missing required option --manifest-id"}

  defp validate_options(positional, invalid, _manifest_id) do
    invalid_options = Enum.map(invalid, fn {option, _value} -> option end)
    {:error, "invalid options: #{Enum.join(positional ++ invalid_options, ", ")}"}
  end

  defp format_errors(errors) do
    errors
    |> Enum.map_join(", ", fn %{path: path, message: message} -> "#{path} #{message}" end)
  end
end
