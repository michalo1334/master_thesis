defmodule NetworkDefense.Evaluation.StudyBundle do
  @moduledoc """
  Builds one deterministic analysis-input study ZIP.

  The bundle contains canonical `study.json`, one immutable tier archive per
  declared tier under `tiers/`, and `checksums.txt` over both. The module does
  not read or rewrite inner tier archives. Statistics stay in the Python
  analysis service.

  `archive/2` writes members in this fixed order: `study.json`, tier archives
  sorted by tier label, then `checksums.txt`. It uses one fixed ZIP timestamp
  for every member so repeated builds produce identical bytes.

  A saved specification declares tiers as labels, for example `["small"]` or
  `[%{"label" => "small"}]`. The Python loader does not accept that form: it
  requires each tier entry to be an object with `label`, `archive`, and
  `sha256`. The private hydration step between the two replaces the declaration
  with one loader-ready object per resolved tier, using the archive member path
  and the SHA-256 of the exact tier bytes.
  """

  alias NetworkDefense.Evaluation.AnalysisLimits
  alias NetworkDefense.Evaluation.StudyTierValidator

  @type tier_input :: %{
          required(:tier) => String.t(),
          required(:run_id) => Ecto.UUID.t(),
          required(:archive) => binary()
        }

  @type tier_entry :: %{
          label: String.t(),
          run_id: String.t(),
          path: String.t(),
          digest: String.t(),
          bytes: binary()
        }

  @archive_timestamp {{1980, 1, 1}, {0, 0, 0}}

  @spec archive([tier_input()], map()) :: {:ok, binary()} | {:error, term()}
  def archive(tiers, study_spec) when is_list(tiers) and is_map(study_spec) do
    with {:ok, study_id} <- study_id(study_spec),
         {:ok, entries} <- tier_entries(tiers),
         :ok <- declared_labels_match(study_spec, entries),
         :ok <- enforce_input_limit(entries),
         {:ok, spec} <- fill_spec(study_spec, study_id, entries) do
      build(spec, entries)
    end
  end

  def archive(_tiers, _study_spec), do: {:error, :invalid_study_spec}

  defp build(spec, entries) do
    with {:ok, bundle} <- zip(bundle_files(spec, entries)),
         :ok <- enforce_output_limit(bundle) do
      {:ok, bundle}
    end
  end

  defp study_id(%{"study_id" => id}) when is_binary(id) and id != "", do: {:ok, id}
  defp study_id(_study_spec), do: {:error, :invalid_study_spec}

  defp tier_entries(tiers) do
    with :ok <- StudyTierValidator.normalize(StudyTierValidator.validate(tiers)),
         {:ok, entries} <- collect_tier_entries(tiers) do
      {:ok, Enum.sort_by(entries, & &1.label)}
    end
  end

  defp collect_tier_entries(tiers) do
    tiers
    |> Enum.reduce_while({:ok, []}, fn tier, {:ok, acc} ->
      case tier_entry(tier) do
        {:ok, entry} -> {:cont, {:ok, [entry | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, _reason} = error -> error
    end
  end

  defp tier_entry(%{tier: label, run_id: run_id, archive: archive}) when is_binary(archive) do
    {:ok, entry(label, run_id, archive)}
  end

  defp tier_entry(_tier), do: {:error, :invalid_tier}

  defp entry(label, run_id, archive) do
    %{
      label: label,
      run_id: run_id,
      path: "tiers/#{label}.zip",
      digest: digest(archive),
      bytes: archive
    }
  end

  defp declared_labels_match(study_spec, entries) do
    case Map.get(study_spec, "tiers") do
      nil ->
        :ok

      declared when is_list(declared) ->
        validate_declared_labels(declared, entries)

      _other ->
        {:error, :invalid_study_spec}
    end
  end

  defp validate_declared_labels(declared, entries) do
    with {:ok, labels} <- declared_labels(declared) do
      declared_set = MapSet.new(labels)

      cond do
        MapSet.size(declared_set) != length(labels) ->
          {:error, :invalid_study_spec}

        declared_set == MapSet.new(Enum.map(entries, & &1.label)) ->
          :ok

        true ->
          {:error, :tier_declaration_mismatch}
      end
    end
  end

  defp declared_labels(declared) do
    Enum.reduce_while(declared, {:ok, []}, fn item, {:ok, acc} ->
      case item do
        label when is_binary(label) -> {:cont, {:ok, [label | acc]}}
        %{"label" => label} when is_binary(label) -> {:cont, {:ok, [label | acc]}}
        _other -> {:halt, {:error, :invalid_study_spec}}
      end
    end)
  end

  # Hydrates a study specification for the Python analysis loader. The saved
  # specification declares tiers as labels; the Python loader requires each tier
  # entry to be an object with `label`, `archive`, and `sha256`, and it checks
  # that digest against the archive bytes. This replaces the declaration with
  # one such object per resolved tier. Other specification keys pass through
  # unchanged.
  @spec fill_spec(map(), String.t(), [tier_entry()]) :: {:ok, map()}
  defp fill_spec(study_spec, study_id, entries) do
    tiers =
      Enum.map(entries, fn entry ->
        %{"label" => entry.label, "archive" => entry.path, "sha256" => entry.digest}
      end)

    {:ok, study_spec |> Map.put("study_id", study_id) |> Map.put("tiers", tiers)}
  end

  defp bundle_files(spec, entries) do
    study = {"study.json", canonical_json(spec)}
    tier_files = Enum.map(entries, &{&1.path, &1.bytes})
    checksums = {"checksums.txt", checksum_lines([study | tier_files])}
    [study | tier_files] ++ [checksums]
  end

  defp checksum_lines(files) do
    files
    |> Enum.map_join("\n", fn {name, content} -> "#{name}  #{digest(content)}" end)
    |> then(&(&1 <> "\n"))
  end

  defp zip(files) do
    entries =
      Enum.map(files, fn {name, content} ->
        {String.to_charlist(name), file_info(content), content}
      end)

    case :zip.create(~c"study.zip", entries, [:memory]) do
      {:ok, {_name, binary}} -> {:ok, binary}
      {:error, reason} -> {:error, {:zip, reason}}
    end
  end

  defp file_info(content) do
    {:file_info, byte_size(content), :regular, :read_write, @archive_timestamp,
     @archive_timestamp, @archive_timestamp, 0o644, 1, 0, 0, 0, 0, 0}
  end

  defp enforce_input_limit(entries) do
    max_bytes = max_bytes()

    if Enum.any?(entries, &(byte_size(&1.bytes) > max_bytes)) do
      {:error, :tier_archive_too_large}
    else
      total = Enum.reduce(entries, 0, &(byte_size(&1.bytes) + &2))

      if total > max_bytes, do: {:error, :input_too_large}, else: :ok
    end
  end

  defp enforce_output_limit(bundle) when is_binary(bundle) do
    if byte_size(bundle) > max_bytes(), do: {:error, :output_too_large}, else: :ok
  end

  defp max_bytes, do: AnalysisLimits.max_zip_bytes()

  defp digest(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)

  defp canonical_json(value), do: value |> ordered_json() |> Jason.encode!()

  defp ordered_json(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(key), ordered_json(item)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp ordered_json(value) when is_list(value), do: Enum.map(value, &ordered_json/1)
  defp ordered_json(value), do: value
end
