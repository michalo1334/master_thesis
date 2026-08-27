defmodule NetworkDefense.Evaluation.AnalysisResult do
  @moduledoc false

  @required ~w(analysis.json metadata.json)

  @comparison_fields ~w(comparison strategy model_variant baseline baseline_model_variant budget)
  @outcome_fields @comparison_fields ++ ~w(outcome)
  @interval_fields ~w(ci_lower ci_upper ci_half_width)

  @primary_fields @outcome_fields ++
                    ~w(paired_mean_difference) ++ @interval_fields ++ ~w(d_z p_raw p_adjusted)
  @secondary_fields @outcome_fields ++ ~w(mean_difference) ++ @interval_fields
  @capability_fields @comparison_fields ++
                       ~w(capability_id tested_probability baseline_probability probability_difference) ++
                       @interval_fields

  @binary_fields ~w(strategy model_variant baseline baseline_model_variant outcome capability_id experiment_id plan_id)
  @nullable_binary_fields ~w(capability_name)
  @nullable_boolean_fields ~w(passes)
  @boolean_fields ~w(pre_attack_feasible)
  @nullable_integer_fields ~w(comparison budget paired_attack_seed_count approximate_trials)
  @nullable_number_fields ~w(
    ci_half_width target paired_mean_difference ci_lower ci_upper d_z p_raw p_adjusted mean_difference
    tested_probability baseline_probability probability_difference
  )
  @non_negative_integer_fields ~w(unavailable_required_flow_count affected_capability_count)

  @row_validators [
    {@binary_fields, :binary},
    {@nullable_binary_fields, :nullable_binary},
    {@nullable_boolean_fields, :nullable_boolean},
    {@boolean_fields, :boolean},
    {@nullable_integer_fields, :nullable_integer},
    {@nullable_number_fields, :nullable_number},
    {@non_negative_integer_fields, :non_negative_integer}
  ]

  @spec parse(binary(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def parse(zip, max_bytes) when is_binary(zip) and is_integer(max_bytes) and max_bytes > 0 do
    with {:ok, entries} <-
           :zip.extract(zip, [:memory, {:file_list, Enum.map(@required, &String.to_charlist/1)}]),
         :ok <- validate_entries(entries, max_bytes),
         {:ok, analysis} <- read_json(entries, "analysis.json", max_bytes),
         {:ok, metadata} <- read_json(entries, "metadata.json", max_bytes),
         :ok <- validate_document(analysis, metadata) do
      {:ok,
       %{
         metadata: metadata,
         pilot_comparison_pass: metadata["pilot_comparison_pass"],
         primary_results: analysis["primary_results"],
         secondary_results: analysis["secondary_results"],
         capability_results: analysis["capability_results"],
         feasibility_summary: analysis["feasibility_summary"]
       }}
    end
  rescue
    _ -> {:error, :invalid_zip}
  end

  defp validate_entries(entries, max_bytes) do
    names = Enum.map(entries, fn {name, _content} -> to_string(name) end)

    cond do
      Enum.count(names, &(&1 in @required)) != length(@required) ->
        {:error, :missing_or_duplicate}

      Enum.any?(entries, fn {name, content} ->
        to_string(name) in @required and byte_size(content) > max_bytes
      end) ->
        {:error, :member_too_large}

      true ->
        :ok
    end
  end

  defp read_json(entries, name, max_bytes) do
    case Enum.find(entries, fn {entry_name, _content} -> to_string(entry_name) == name end) do
      {_entry_name, content} when byte_size(content) <= max_bytes ->
        case Jason.decode(content) do
          {:ok, value} when is_map(value) -> {:ok, value}
          _ -> {:error, {:malformed, name}}
        end

      {_entry_name, _content} ->
        {:error, :member_too_large}

      nil ->
        {:error, {:missing, name}}
    end
  end

  defp validate_document(analysis, metadata) do
    with :ok <-
           required_map_fields(
             metadata,
             ~w(manifest_id schema_version model_version command_mode)
           ),
         :ok <- required_list_fields(metadata, ["pilot_comparison_pass", "model_variants"]),
         :ok <- required_map_fields(metadata, ["runtime_summary"]),
         :ok <-
           required_list_fields(analysis, [
             "primary_results",
             "secondary_results",
             "capability_results",
             "feasibility_summary"
           ]),
         :ok <-
           rows(
             metadata["pilot_comparison_pass"],
             ~w(comparison ci_half_width target passes paired_attack_seed_count approximate_trials)
           ),
         :ok <-
           rows(
             analysis["primary_results"],
             @primary_fields
           ),
         :ok <-
           rows(
             analysis["secondary_results"],
             @secondary_fields
           ),
         :ok <-
           rows(
             analysis["capability_results"],
             @capability_fields
           ),
         :ok <-
           rows(
             analysis["feasibility_summary"],
             ~w(experiment_id plan_id pre_attack_feasible unavailable_required_flow_count affected_capability_count)
           ) do
      runtime_summary(metadata["runtime_summary"])
    end
  end

  defp required_map_fields(map, fields) do
    if Enum.all?(fields, &Map.has_key?(map, &1)), do: :ok, else: {:error, :missing_field}
  end

  defp required_list_fields(map, fields) do
    if Enum.all?(fields, &is_list(map[&1])), do: :ok, else: {:error, :malformed_field}
  end

  defp rows(rows, fields) do
    if Enum.all?(
         rows,
         &(is_map(&1) and Enum.all?(fields, fn field -> Map.has_key?(&1, field) end) and
             valid_row?(&1))
       ), do: :ok, else: {:error, :malformed_row}
  end

  defp valid_row?(row) do
    Enum.all?(@row_validators, fn {fields, validator} -> valid_fields?(row, fields, validator) end)
  end

  defp runtime_summary(summary) do
    fields =
      ~w(median_plan_selection_runtime_ms median_simulation_runtime_ms evaluator_runtime_ms)

    if Enum.all?(fields, &(is_number(summary[&1]) and summary[&1] >= 0)),
      do: :ok,
      else: {:error, :malformed_runtime_summary}
  end

  defp valid_fields?(row, fields, validator) do
    Enum.all?(fields, fn field ->
      not Map.has_key?(row, field) or validate(validator, row[field])
    end)
  end

  defp validate(:binary, value), do: is_binary(value)
  defp validate(:nullable_binary, value), do: is_binary(value) or is_nil(value)
  defp validate(:nullable_boolean, value), do: is_boolean(value) or is_nil(value)
  defp validate(:boolean, value), do: is_boolean(value)
  defp validate(:nullable_integer, value), do: is_integer(value) or is_nil(value)
  defp validate(:nullable_number, value), do: is_number(value) or is_nil(value)
  defp validate(:non_negative_integer, value), do: is_integer(value) and value >= 0
end
