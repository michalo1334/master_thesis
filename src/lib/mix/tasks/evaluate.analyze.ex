defmodule Mix.Tasks.Evaluate.Analyze do
  use Mix.Task

  @shortdoc "Analyze a completed evaluation archive"
  @moduledoc """
  Sends a completed evaluation export to the configured analysis service.

      mix evaluate.analyze --run-id RUN_ID --mode analyze --output analysis.zip
  """

  @requirements ["app.start"]
  @switches [run_id: :string, mode: :string, output: :string]

  alias NetworkDefense.Evaluation

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    with :ok <- validate_options(options, positional, invalid),
         {:ok, result} <- Evaluation.analyze(options[:run_id], options[:mode]),
         :ok <- File.mkdir_p(Path.dirname(options[:output])),
         :ok <- File.write(options[:output], result) do
      IO.puts(
        Jason.encode!(%{
          "run_id" => options[:run_id],
          "mode" => options[:mode],
          "path" => options[:output],
          "byte_size" => byte_size(result),
          "sha256" => Base.encode16(:crypto.hash(:sha256, result), case: :lower)
        })
      )
    else
      {:error, reason} -> Mix.raise(error_message(reason))
    end
  end

  defp validate_options(options, [], []) do
    Enum.find_value([:run_id, :mode, :output], :ok, fn option ->
      if is_nil(options[option]) do
        flag = option |> Atom.to_string() |> String.replace("_", "-")
        {:error, "missing required option --#{flag}"}
      end
    end)
  end

  defp validate_options(_options, positional, invalid) do
    names = Enum.map(invalid, fn {name, _value} -> to_string(name) end)
    {:error, "invalid options: #{Enum.join(positional ++ names, ", ")}"}
  end

  defp error_message(:not_found), do: "evaluation run not found"
  defp error_message(:incomplete), do: "evaluation run is not complete"
  defp error_message(:not_configured), do: "analysis service is not configured"
  defp error_message(:transport), do: "analysis service transport failed"
  defp error_message(:http_status), do: "analysis service returned a non-success status"
  defp error_message(:content_type), do: "analysis service returned an invalid content type"
  defp error_message(:response_too_large), do: "analysis service response is too large"
  defp error_message(:invalid_body), do: "analysis service returned an invalid body"
  defp error_message(:invalid_mode), do: "mode must be pilot or analyze"
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: "analysis failed: #{inspect(reason)}"
end
