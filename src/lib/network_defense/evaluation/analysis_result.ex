defmodule NetworkDefense.Evaluation.AnalysisResult do
  @moduledoc false

  @required ~w(analysis.json metadata.json)

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
         capability_results: analysis["capability_results"]
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
         :ok <-
           required_list_fields(analysis, [
             "primary_results",
             "secondary_results",
             "capability_results"
           ]),
         :ok <-
           rows(
             metadata["pilot_comparison_pass"],
             ~w(comparison ci_half_width target passes paired_attack_seed_count approximate_trials)
           ),
         :ok <-
           rows(
             analysis["primary_results"],
             ~w(comparison strategy model_variant baseline baseline_model_variant budget outcome paired_mean_difference ci_lower ci_upper ci_half_width d_z p_raw p_adjusted)
           ),
         :ok <-
           rows(
             analysis["secondary_results"],
             ~w(comparison strategy model_variant baseline baseline_model_variant budget outcome mean_difference ci_lower ci_upper ci_half_width)
           ) do
      rows(
        analysis["capability_results"],
        ~w(comparison strategy model_variant baseline baseline_model_variant budget capability_id tested_probability baseline_probability probability_difference ci_lower ci_upper ci_half_width)
      )
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
    valid_fields?(
      row,
      ~w(strategy model_variant baseline baseline_model_variant outcome capability_id),
      &is_binary/1
    ) and
      valid_fields?(row, ~w(capability_name), &(is_binary(&1) or is_nil(&1))) and
      valid_fields?(row, ~w(passes), &(is_boolean(&1) or is_nil(&1))) and
      valid_fields?(
        row,
        ~w(comparison budget paired_attack_seed_count approximate_trials),
        &(is_integer(&1) or is_nil(&1))
      ) and
      valid_fields?(
        row,
        ~w(ci_half_width target paired_mean_difference ci_lower ci_upper d_z p_raw p_adjusted mean_difference tested_probability baseline_probability probability_difference),
        &(is_number(&1) or is_nil(&1))
      )
  end

  defp valid_fields?(row, fields, validator) do
    Enum.all?(fields, fn field -> not Map.has_key?(row, field) or validator.(row[field]) end)
  end
end
