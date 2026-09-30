defmodule NetworkDefense.Evaluation.AnalysisResult do
  @moduledoc false

  @legacy_files ~w(analysis.json metadata.json)
  @study_metadata_file "study_metadata.json"
  @study_primary_file "primary_results.json"
  @study_pilot_file "pilot_results.json"
  @checksums_file "checksums.txt"
  @study_analyze_files ~w(
    study_metadata.json primary_results.csv primary_results.json tier_context.json checksums.txt
  )
  @study_pilot_files ~w(
    study_metadata.json pilot_results.csv pilot_results.json checksums.txt
  )

  @comparison_fields ~w(comparison strategy model_variant baseline baseline_model_variant budget)
  @outcome_fields @comparison_fields ++ ~w(outcome)
  @interval_fields ~w(ci_lower ci_upper ci_half_width)

  @legacy_primary_fields @outcome_fields ++
                           ~w(paired_mean_difference) ++
                           @interval_fields ++ ~w(d_z p_raw p_adjusted)

  @primary_fields @legacy_primary_fields ++
                    ~w(
                      comparison_id tier informative tested_plan_count baseline_plan_count
                      attacks_per_plan
                    )

  @secondary_fields @outcome_fields ++ ~w(mean_difference) ++ @interval_fields
  @capability_fields @comparison_fields ++
                       ~w(capability_id tested_probability baseline_probability probability_difference) ++
                       @interval_fields

  @study_pilot_fields ~w(
    comparison_id tier informative candidate_plan_count candidate_attacks_per_plan
    guarded_ci_half_width target passes
  )

  @binary_fields ~w(strategy model_variant baseline baseline_model_variant outcome capability_id experiment_id plan_id)
  @nullable_binary_fields ~w(capability_name tier comparison_id)
  @nullable_boolean_fields ~w(passes informative insufficient_pilot)
  @boolean_fields ~w(pre_attack_feasible)
  @nullable_integer_fields ~w(
    comparison budget tested_plan_count baseline_plan_count
    attacks_per_plan candidate_plan_count candidate_attacks_per_plan
    recommended_plan_selection_seed_count recommended_attacks_per_plan
  )
  @nullable_number_fields ~w(
    ci_half_width target guarded_ci_half_width paired_mean_difference ci_lower ci_upper d_z p_raw
    p_adjusted mean_difference tested_probability baseline_probability probability_difference
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
    with {:ok, members} <- list_members(zip),
         {:ok, format, files} <- classify(Enum.map(members, & &1.name)),
         :ok <- validate_members(members, files, format, max_bytes),
         {:ok, entries} <- extract_entries(zip, files),
         :ok <- validate_entries(entries, files, format, max_bytes),
         :ok <- validate_checksums(entries, format) do
      build(format, entries, max_bytes)
    end
  rescue
    _ -> {:error, :invalid_zip}
  end

  defp list_members(zip) do
    case :zip.list_dir(zip) do
      {:ok, entries} ->
        members =
          for {:zip_file, name, info, _comment, _offset, _comp_size} <- entries do
            %{name: to_string(name), uncompressed_size: elem(info, 1)}
          end

        {:ok, members}

      {:error, _reason} ->
        {:error, :invalid_zip}
    end
  end

  defp validate_members(members, files, format, max_bytes) do
    names = Enum.map(members, & &1.name)

    case validate_member_set(names, files, format) do
      :ok -> validate_declared_sizes(members, max_bytes)
      {:error, _reason} = error -> error
    end
  end

  defp validate_member_set(names, files, format) when format in [:study_analyze, :study_pilot] do
    if Enum.sort(names) == Enum.sort(files), do: :ok, else: {:error, :unexpected_member}
  end

  defp validate_member_set(names, files, :legacy) do
    if Enum.all?(files, fn file -> Enum.count(names, &(&1 == file)) == 1 end),
      do: :ok,
      else: {:error, :missing_or_duplicate}
  end

  defp validate_declared_sizes(members, max_bytes) do
    total =
      Enum.reduce_while(members, {:ok, 0}, fn
        %{uncompressed_size: size}, {:ok, total}
        when is_integer(size) and size >= 0 and size <= max_bytes ->
          next_total = total + size

          if next_total <= max_bytes,
            do: {:cont, {:ok, next_total}},
            else: {:halt, {:error, :archive_too_large}}

        _member, _acc ->
          {:halt, {:error, :member_too_large}}
      end)

    case total do
      {:ok, _size} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp classify(names) do
    legacy? = Enum.all?(@legacy_files, fn file -> Enum.count(names, &(&1 == file)) == 1 end)
    metadata? = Enum.count(names, &(&1 == @study_metadata_file)) == 1
    primary? = Enum.count(names, &(&1 == @study_primary_file))
    pilot? = Enum.count(names, &(&1 == @study_pilot_file))

    cond do
      metadata? and primary? == 1 and pilot? == 0 ->
        {:ok, :study_analyze, @study_analyze_files}

      metadata? and pilot? == 1 and primary? == 0 ->
        {:ok, :study_pilot, @study_pilot_files}

      legacy? ->
        {:ok, :legacy, @legacy_files}

      true ->
        {:error, :missing_or_duplicate}
    end
  end

  defp extract_entries(zip, files) do
    case :zip.extract(zip, [:memory, {:file_list, Enum.map(files, &String.to_charlist/1)}]) do
      {:ok, entries} -> {:ok, entries}
      {:error, _reason} -> {:error, :invalid_zip}
    end
  end

  defp build(:legacy, entries, max_bytes) do
    with {:ok, analysis} <- read_json(entries, "analysis.json", max_bytes),
         {:ok, metadata} <- read_json(entries, "metadata.json", max_bytes),
         :ok <- validate_legacy_document(analysis, metadata) do
      {:ok,
       result_map(
         metadata,
         [],
         analysis["primary_results"],
         analysis["secondary_results"],
         analysis["capability_results"],
         analysis["feasibility_summary"]
       )}
    end
  end

  defp build(:study_analyze, entries, max_bytes) do
    with {:ok, metadata} <- read_json(entries, @study_metadata_file, max_bytes),
         {:ok, primary_results} <- read_json_list(entries, @study_primary_file, max_bytes),
         :ok <- validate_study_metadata(metadata),
         :ok <- validate_study_command_mode(metadata, "study-analyze"),
         :ok <- rows(primary_results, @primary_fields) do
      {:ok, result_map(metadata, [], primary_results, [], [], [])}
    end
  end

  defp build(:study_pilot, entries, max_bytes) do
    with {:ok, metadata} <- read_json(entries, @study_metadata_file, max_bytes),
         {:ok, pilot_results} <- read_json_list(entries, @study_pilot_file, max_bytes),
         :ok <- validate_study_metadata(metadata),
         :ok <- validate_study_command_mode(metadata, "study-pilot"),
         :ok <- rows(pilot_results, @study_pilot_fields) do
      {:ok, result_map(metadata, pilot_results, [], [], [], [])}
    end
  end

  defp result_map(metadata, pilot_results, primary, secondary, capability, feasibility) do
    %{
      metadata: metadata,
      pilot_results: pilot_results,
      primary_results: primary,
      secondary_results: secondary,
      capability_results: capability,
      feasibility_summary: feasibility
    }
  end

  defp validate_entries(entries, files, format, max_bytes) do
    names = Enum.map(entries, fn {name, _content} -> to_string(name) end)

    total_bytes =
      Enum.reduce(entries, 0, fn {_name, content}, total -> total + byte_size(content) end)

    cond do
      format in [:study_analyze, :study_pilot] and Enum.sort(names) != Enum.sort(files) ->
        {:error, :unexpected_member}

      Enum.any?(files, fn file -> Enum.count(names, &(&1 == file)) != 1 end) ->
        {:error, :missing_or_duplicate}

      total_bytes > max_bytes ->
        {:error, :archive_too_large}

      Enum.any?(entries, fn {_name, content} -> byte_size(content) > max_bytes end) ->
        {:error, :member_too_large}

      true ->
        :ok
    end
  end

  defp validate_checksums(_entries, :legacy), do: :ok

  defp validate_checksums(entries, format) when format in [:study_analyze, :study_pilot] do
    payload_files = Enum.reject(study_files(format), &(&1 == @checksums_file))

    with {:ok, checksums} <- checksum_entries(entries),
         :ok <- checksum_coverage(checksums, payload_files) do
      verify_checksums(entries, checksums)
    end
  end

  defp study_files(:study_analyze), do: @study_analyze_files
  defp study_files(:study_pilot), do: @study_pilot_files

  defp checksum_entries(entries) do
    case Enum.find(entries, fn {name, _content} -> to_string(name) == @checksums_file end) do
      {_name, content} -> parse_checksum_lines(content)
      nil -> {:error, :missing_or_duplicate}
    end
  end

  defp parse_checksum_lines(content) do
    with {:ok, lines} <- checksum_lines(content) do
      collect_checksum_lines(lines)
    end
  end

  defp checksum_lines(content) do
    if String.contains?(content, "\n\n") do
      {:error, :invalid_checksum}
    else
      {:ok, content |> String.trim_trailing("\n") |> String.split("\n")}
    end
  end

  defp collect_checksum_lines(lines) do
    Enum.reduce_while(lines, {:ok, %{}}, fn line, {:ok, checksums} ->
      case Regex.run(~r/\A([^\s]+)  ([0-9a-f]{64})\z/, line) do
        [_, name, digest] when not is_map_key(checksums, name) ->
          {:cont, {:ok, Map.put(checksums, name, digest)}}

        _invalid ->
          {:halt, {:error, :invalid_checksum}}
      end
    end)
  end

  defp checksum_coverage(checksums, files) do
    if Map.keys(checksums) |> MapSet.new() == MapSet.new(files),
      do: :ok,
      else: {:error, :invalid_checksum}
  end

  defp verify_checksums(entries, checksums) do
    Enum.reduce_while(checksums, :ok, fn {name, digest}, :ok ->
      case verify_checksum(entries, name, digest) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp verify_checksum(entries, name, digest) do
    case Enum.find(entries, fn {entry_name, _content} -> to_string(entry_name) == name end) do
      {_entry_name, content} ->
        if digest(content) == digest, do: :ok, else: {:error, :checksum_mismatch}

      nil ->
        {:error, :missing_or_duplicate}
    end
  end

  defp digest(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)

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

  defp read_json_list(entries, name, max_bytes) do
    case Enum.find(entries, fn {entry_name, _content} -> to_string(entry_name) == name end) do
      {_entry_name, content} when byte_size(content) <= max_bytes ->
        case Jason.decode(content) do
          {:ok, value} when is_list(value) -> {:ok, value}
          _ -> {:error, {:malformed, name}}
        end

      {_entry_name, _content} ->
        {:error, :member_too_large}

      nil ->
        {:error, {:missing, name}}
    end
  end

  defp validate_legacy_document(analysis, metadata) do
    with :ok <-
           required_map_fields(
             metadata,
             ~w(manifest_id schema_version model_version command_mode)
           ),
         :ok <- required_list_fields(metadata, ["model_variants"]),
         :ok <- required_map_fields(metadata, ["runtime_summary"]),
         :ok <-
           required_list_fields(analysis, [
             "primary_results",
             "secondary_results",
             "capability_results",
             "feasibility_summary"
           ]),
         :ok <- rows(analysis["primary_results"], @legacy_primary_fields),
         :ok <- rows(analysis["secondary_results"], @secondary_fields),
         :ok <- rows(analysis["capability_results"], @capability_fields),
         :ok <-
           rows(
             analysis["feasibility_summary"],
             ~w(experiment_id plan_id pre_attack_feasible unavailable_required_flow_count affected_capability_count)
           ) do
      runtime_summary(metadata["runtime_summary"])
    end
  end

  defp validate_study_metadata(metadata) do
    with :ok <-
           required_map_fields(
             metadata,
             ~w(
               study_id specification_version family_scope family_size command_mode
               multiplicity_correction expected_family
             )
           ),
         :ok <-
           required_list_fields(metadata, ["tier_labels", "uncertainty_sources", "tier_context"]),
         :ok <- validate_binary(metadata["study_id"]),
         :ok <- validate_positive_integer(metadata["specification_version"]),
         :ok <- validate_binary(metadata["family_scope"]),
         :ok <- validate_positive_integer(metadata["family_size"]),
         :ok <- validate_binary(metadata["command_mode"]),
         :ok <- validate_multiplicity_correction(metadata["multiplicity_correction"]),
         :ok <- validate_map(metadata["expected_family"]),
         :ok <- validate_tier_context(metadata["tier_context"]) do
      validate_metadata_types(metadata)
    end
  end

  defp validate_metadata_types(metadata) do
    if valid_fields?(metadata, @nullable_binary_fields, :nullable_binary) and
         valid_fields?(metadata, @nullable_boolean_fields, :nullable_boolean) and
         valid_fields?(metadata, @nullable_integer_fields, :nullable_integer) and
         valid_fields?(metadata, @nullable_number_fields, :nullable_number) do
      :ok
    else
      {:error, :malformed_field}
    end
  end

  defp validate_tier_context(context) when is_list(context) and context != [] do
    case collect_tier_context(context) do
      {:ok, entries} -> unique_tier_context(entries)
      {:error, _reason} = error -> error
    end
  end

  defp validate_tier_context(_context), do: {:error, :malformed_field}

  defp collect_tier_context(context) do
    Enum.reduce_while(context, {:ok, []}, fn entry, {:ok, entries} ->
      case tier_context_entry(entry) do
        {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
        :error -> {:halt, {:error, :malformed_field}}
      end
    end)
  end

  defp tier_context_entry(%{"label" => label, "archive" => archive, "archive_sha256" => digest})
       when is_binary(label) and label != "" and is_binary(archive) and archive != "" and
              is_binary(digest) do
    if valid_digest?(digest), do: {:ok, {label, archive, digest}}, else: :error
  end

  defp tier_context_entry(_entry), do: :error

  defp unique_tier_context(entries) do
    labels = Enum.map(entries, &elem(&1, 0))
    archives = Enum.map(entries, &elem(&1, 1))

    if length(labels) == length(Enum.uniq(labels)) and
         length(archives) == length(Enum.uniq(archives)) do
      :ok
    else
      {:error, :malformed_field}
    end
  end

  defp valid_digest?(digest), do: String.match?(digest, ~r/\A[0-9a-f]{64}\z/)

  defp validate_study_command_mode(%{"command_mode" => expected}, expected), do: :ok
  defp validate_study_command_mode(_metadata, _expected), do: {:error, :malformed_field}

  defp validate_binary(value) when is_binary(value), do: :ok
  defp validate_binary(_value), do: {:error, :malformed_field}

  defp validate_map(value) when is_map(value), do: :ok
  defp validate_map(_value), do: {:error, :malformed_field}

  defp validate_positive_integer(value) when is_integer(value) and value > 0, do: :ok
  defp validate_positive_integer(_value), do: {:error, :malformed_field}

  defp validate_multiplicity_correction("holm"), do: :ok
  defp validate_multiplicity_correction(_value), do: {:error, :malformed_field}

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
