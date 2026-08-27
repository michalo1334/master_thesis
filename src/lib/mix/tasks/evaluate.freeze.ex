defmodule Mix.Tasks.Evaluate.Freeze do
  use Mix.Task

  @shortdoc "Freeze a topology-source manifest into a graph-revision manifest"

  @moduledoc """
  Resolves and persists the source topology once, then saves a new
  graph-revision manifest under the frozen manifest id. The title defaults to
  that id.

  SOURCE must be a saved topology-source manifest. The target id must not
  already exist.

      mix evaluate.freeze --manifest-id fixed-enterprise-v1 --frozen-manifest-id frozen-v1
  """

  @requirements ["app.start"]
  @switches [manifest_id: :string, frozen_manifest_id: :string, title: :string]

  alias NetworkDefense.Evaluation

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    with :ok <- validate_options(positional, invalid, options),
         {:ok, result} <-
           Evaluation.freeze(
             options[:manifest_id],
             options[:frozen_manifest_id],
             options[:title]
           ) do
      IO.puts(Jason.encode!(result))
    else
      {:error, :not_found} ->
        Mix.raise("source manifest not found")

      {:error, :target_exists} ->
        Mix.raise("frozen manifest id already exists")

      {:error, :source_not_topology} ->
        Mix.raise("source manifest must be a topology-source manifest")

      {:error, :invalid_target_manifest_id} ->
        Mix.raise("frozen manifest id must be between 1 and 255 bytes")

      {:error, :invalid_title} ->
        Mix.raise("title must be between 1 and 255 bytes")

      {:error, errors} when is_list(errors) ->
        Mix.raise(format_errors(errors))

      {:error, reason} when is_binary(reason) ->
        Mix.raise(reason)
    end
  end

  defp validate_options([], [], options) do
    cond do
      not is_binary(options[:manifest_id]) ->
        {:error, "missing required option --manifest-id"}

      not is_binary(options[:frozen_manifest_id]) ->
        {:error, "missing required option --frozen-manifest-id"}

      true ->
        :ok
    end
  end

  defp validate_options(positional, invalid, _options) do
    invalid_options = Enum.map(invalid, fn {option, _value} -> option end)
    {:error, "invalid options: #{Enum.join(positional ++ invalid_options, ", ")}"}
  end

  defp format_errors(errors) do
    errors
    |> Enum.map_join(", ", fn %{path: path, message: message} -> "#{path} #{message}" end)
  end
end
