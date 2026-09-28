defmodule Mix.Tasks.Evaluate.Study do
  use Mix.Task

  @shortdoc "Build and submit a study bundle from completed tier runs"

  @moduledoc """
  Builds one deterministic study ZIP from completed tier runs and sends it to
  the configured analysis service.

      mix evaluate.study \\
        --spec evaluation/studies/topology-scale.json \\
        --tier small=RUN_ID \\
        --tier medium=RUN_ID \\
        --tier large=RUN_ID \\
        --mode pilot \\
        --output study-pilot.zip

  `--tier` is repeatable and accepts `label=RUN_ID`. `--mode` is `pilot` or
  `analyze`.
  """

  @requirements ["app.start"]
  @switches [spec: :string, tier: :keep, mode: :string, output: :string]

  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.StudyTierValidator

  @impl Mix.Task
  def run(args) do
    {options, positional, invalid} = OptionParser.parse(args, strict: @switches)

    with :ok <- validate_options(options, positional, invalid),
         {:ok, study_spec} <- load_spec(options[:spec]),
         {:ok, mode} <- parse_mode(options[:mode]),
         {:ok, tier_runs} <- parse_tiers(Keyword.get_values(options, :tier)),
         {:ok, result} <- Evaluation.analyze_study(tier_runs, mode, study_spec),
         :ok <- File.mkdir_p(Path.dirname(options[:output])),
         :ok <- File.write(options[:output], result) do
      IO.puts(
        Jason.encode!(%{
          "study_id" => study_spec["study_id"],
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
    Enum.find_value([:spec, :mode, :output], :ok, fn option ->
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

  defp load_spec(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
          {:ok, _other} -> {:error, "study spec must be a JSON object"}
          {:error, error} -> {:error, "invalid study spec JSON: #{Exception.message(error)}"}
        end

      {:error, reason} ->
        {:error, "cannot read study spec: #{reason}"}
    end
  end

  defp parse_mode("pilot"), do: {:ok, :pilot}
  defp parse_mode("analyze"), do: {:ok, :analyze}
  defp parse_mode(_mode), do: {:error, "mode must be pilot or analyze"}

  defp parse_tiers([]), do: {:error, "missing required option --tier"}

  defp parse_tiers(values) do
    with {:ok, pairs} <- parse_tier_values(values),
         :ok <- validate_tier_pairs(pairs) do
      {:ok, pairs}
    end
  end

  defp parse_tier_values(values) do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case parse_tier_value(value) do
        {:ok, pair} -> {:cont, {:ok, [pair | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, pairs} -> {:ok, Enum.reverse(pairs)}
      {:error, _reason} = error -> error
    end
  end

  defp parse_tier_value(value) do
    case String.split(value, "=", parts: 2) do
      [label, run_id] when label != "" ->
        {:ok, {label, run_id}}

      [_label, _run_id] ->
        {:error, "tier label must not be empty"}

      _other ->
        {:error, "invalid --tier value: #{value}"}
    end
  end

  defp validate_tier_pairs(pairs) do
    case StudyTierValidator.validate(pairs) do
      :ok ->
        :ok

      {:error, {:invalid_run_id, {label, run_id}}} ->
        {:error, "invalid tier run id in --tier #{label}=#{run_id}"}

      {:error, reason} ->
        {:error, tier_error_message(reason)}
    end
  end

  defp tier_error_message(:unsafe_tier_label), do: "tier label is unsafe"
  defp tier_error_message(:invalid_tier), do: "invalid --tier value"
  defp tier_error_message(:no_tiers), do: "missing required option --tier"
  defp tier_error_message(:duplicate_tier_label), do: "duplicate tier label"
  defp tier_error_message(:duplicate_run_id), do: "duplicate tier run id"

  defp error_message(:not_found), do: "evaluation run not found"
  defp error_message(:incomplete), do: "evaluation run is not complete"
  defp error_message(:not_exportable), do: "evaluation run is a warm-up and cannot be analyzed"
  defp error_message(:not_configured), do: "analysis service is not configured"
  defp error_message(:transport), do: "analysis service transport failed"
  defp error_message(:http_status), do: "analysis service returned a non-success status"
  defp error_message(:content_type), do: "analysis service returned an invalid content type"
  defp error_message(:response_too_large), do: "analysis service response is too large"
  defp error_message(:invalid_body), do: "analysis service returned an invalid body"
  defp error_message(:invalid_mode), do: "mode must be pilot or analyze"
  defp error_message(:invalid_study_spec), do: "study specification is invalid"
  defp error_message(:invalid_study_tiers), do: "tier run list is invalid"
  defp error_message(:invalid_run_id), do: "tier run id is invalid"
  defp error_message(:no_tiers), do: "at least one --tier is required"
  defp error_message(:unsafe_tier_label), do: "tier label is unsafe"
  defp error_message(:duplicate_tier_label), do: "tier labels must be unique"
  defp error_message(:duplicate_run_id), do: "tier run ids must be unique"

  defp error_message(:tier_declaration_mismatch),
    do: "study tier labels do not match --tier values"

  defp error_message(:tier_archive_too_large),
    do: "tier archive exceeds the configured byte limit"

  defp error_message(:input_too_large), do: "study input exceeds the configured byte limit"
  defp error_message(:output_too_large), do: "study bundle exceeds the configured byte limit"
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message({:zip, reason}), do: "study bundle packaging failed: #{inspect(reason)}"
  defp error_message(reason), do: "study analysis failed: #{inspect(reason)}"
end
