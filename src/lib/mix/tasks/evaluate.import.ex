defmodule Mix.Tasks.Evaluate.Import do
  use Mix.Task

  @shortdoc "Import a versioned JSON evaluation manifest"

  @moduledoc """
  Imports a saved manifest from a JSON file. The manifest `id` becomes the
  saved manifest id; the title defaults to that id.

  Re-importing identical content is a no-op. Importing the same id with
  different content fails rather than overwriting the saved manifest.

      mix evaluate.import --file fixed-enterprise-v1.json --title "Fixed enterprise"
  """

  @requirements ["app.start"]
  @switches [file: :string, title: :string]

  alias NetworkDefense.Evaluation

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    with :ok <- validate_options(positional, invalid, options[:file]),
         {:ok, result} <- import_from_file(options[:file], options[:title]) do
      IO.puts(Jason.encode!(result))
    else
      {:error, :missing_file} -> Mix.raise("file not found: #{options[:file]}")
      {:error, :conflict} -> Mix.raise("manifest already exists with different content")
      {:error, errors} when is_list(errors) -> Mix.raise(format_errors(errors))
      {:error, reason} when is_binary(reason) -> Mix.raise(reason)
    end
  end

  defp import_from_file(path, title) do
    case File.read(path) do
      {:ok, json} -> Evaluation.import_manifest(json, title)
      {:error, _reason} -> {:error, :missing_file}
    end
  end

  defp validate_options([], [], file) when is_binary(file), do: :ok

  defp validate_options([], [], _file),
    do: {:error, "missing required option --file"}

  defp validate_options(positional, invalid, _file) do
    invalid_options = Enum.map(invalid, fn {option, _value} -> option end)
    {:error, "invalid options: #{Enum.join(positional ++ invalid_options, ", ")}"}
  end

  defp format_errors(errors) do
    errors
    |> Enum.map_join(", ", fn %{path: path, message: message} -> "#{path} #{message}" end)
  end
end
