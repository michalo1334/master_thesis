defmodule Mix.Tasks.Evaluate.Warmup do
  use Mix.Task

  @shortdoc "Run a saved manifest as a warm-up"

  @moduledoc """
  Runs a saved manifest once synchronously as a warm-up. The run shares the
  evaluation lifecycle and measurements but can never be exported or analyzed.

      mix evaluate.warmup --manifest-id fixed-enterprise-v1
  """

  @requirements ["app.start"]
  @switches [manifest_id: :string]

  alias NetworkDefense.Evaluation

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    with :ok <- validate_options(positional, invalid, options[:manifest_id]),
         {:ok, run} <- Evaluation.warm_up(options[:manifest_id]) do
      IO.puts(
        Jason.encode!(%{
          "evaluation_run_id" => run.id,
          "manifest_id" => options[:manifest_id],
          "purpose" => run.purpose,
          "status" => run.status
        })
      )
    else
      {:error, :not_found} -> Mix.raise("evaluation manifest not found")
      {:error, errors} when is_list(errors) -> Mix.raise(format_errors(errors))
      {:error, reason} when is_binary(reason) -> Mix.raise(reason)
      {:error, reason} -> Mix.raise("warm-up failed: #{inspect(reason)}")
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
