defmodule NetworkDefense.Evaluation.Study.Contracts.Definition do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Changeset
  alias NetworkDefense.Contracts
  alias NetworkDefense.Evaluation.JsonBoundary
  alias NetworkDefense.Evaluation.Study.Contracts.{DefinitionConsistency, StudyError}
  alias NetworkDefense.Evaluation.Study.SchemaValidator

  alias NetworkDefense.Evaluation.Study.Contracts.Definition.{
    Family,
    Final,
    Graph,
    Pilot,
    PilotToFinal,
    Simulation,
    Study
  }

  # The complete, normalized study definition.
  #
  # One definition holds every executable setting for Pilot and for Final, so a
  # later phase reads a setting and never invents one. Two entry points exist:
  #
  # - `parse/1` accepts the JSON-compatible map that the YAML boundary returns.
  #   It rejects a non-string key, an invalid UTF-8 key, an invalid UTF-8 value,
  #   an unknown field, a raw value that would need coercion, an out-of-bound
  #   value, an unrepresentable number, and a definition whose settings
  #   disagree;
  # - `to_params/1` returns the normalized string-keyed form. Parsing that form
  #   again returns an equal struct, so a stored definition round-trips.
  #
  # The traversal limits are operational limits from decision D0, and they are
  # per collection: one map or one list holds at most 10,000 entries, and the
  # document nests at most 32 levels. No aggregate document limit exists, so a
  # document with many individually valid collections is accepted.
  #
  # The definition holds reference strings, not records. Only a graph revision
  # identifier has a record and a loader. The remaining revision strings are
  # bounded caller assertions: this module checks that they are present, typed,
  # and bounded, and it does not authenticate them.
  #
  # A non-scoring strategy declares no scoring block, so normalization omits
  # the absent keys instead of writing nulls. That is why this module converts
  # the definition itself and does not rely on the shared struct conversion.

  @definition_limit 1_048_576
  @max_depth 32
  @max_entries 10_000

  # Every float-backed setting. Ecto converts each one with `:erlang.float/1`,
  # which raises for an integer beyond float range even though the raw schema
  # accepts that number. The technical check below names the field before Ecto
  # reaches it. It states a conversion limit, not a scientific maximum, and it
  # replaces no value.
  @float_paths [
    ["family", "alpha"],
    ["pilot", "analysis", "target_half_width"],
    ["pilot", "analysis", "guard_quantile"],
    ["pilot", "analysis", "confidence_level"],
    ["final", "analysis", "alpha"],
    ["final", "analysis", "confidence_level"]
  ]

  @type t :: %__MODULE__{
          schema_version: integer(),
          study: Study.t(),
          graphs: [Graph.t()],
          simulation: Simulation.t(),
          family: Family.t(),
          pilot: Pilot.t(),
          pilot_to_final: PilotToFinal.t(),
          final: Final.t()
        }

  @primary_key false

  embedded_schema do
    field :schema_version, :integer
    embeds_one :study, Study, on_replace: :update
    embeds_many :graphs, Graph, on_replace: :delete
    embeds_one :simulation, Simulation, on_replace: :update
    embeds_one :family, Family, on_replace: :update
    embeds_one :pilot, Pilot, on_replace: :update
    embeds_one :pilot_to_final, PilotToFinal, on_replace: :update
    embeds_one :final, Final, on_replace: :update
  end

  def changeset(definition, attrs) do
    definition
    |> change()
    |> SchemaValidator.matches_schema(attrs, :definition)
    |> cast_if_schema_valid(attrs)
  end

  @spec parse(term()) :: {:ok, t()} | {:error, StudyError.t()}
  def parse(attrs) when is_map(attrs) do
    with :ok <- json_structure(attrs),
         :ok <- representable_numbers(attrs),
         {:ok, encoded} <- encode(attrs),
         :ok <- within_limit(encoded),
         {:ok, definition} <- materialize(attrs),
         :ok <- DefinitionConsistency.validate(definition),
         {:ok, normalized} <- definition |> to_params() |> encode(),
         :ok <- within_limit(normalized) do
      {:ok, definition}
    end
  end

  def parse(_attrs), do: {:error, StudyError.invalid_json_value([])}

  @spec to_params(t()) :: map()
  def to_params(%__MODULE__{} = definition) do
    definition
    |> Contracts.to_params()
    |> Map.update!("graphs", fn graphs -> Enum.map(graphs, &normalize_graph/1) end)
  end

  defp normalize_graph(graph) do
    Map.update!(graph, "strategies", fn strategies ->
      Enum.map(strategies, &Map.reject(&1, fn {_key, value} -> is_nil(value) end))
    end)
  end

  defp cast_if_schema_valid(%Changeset{valid?: false} = changeset, _attrs), do: changeset

  defp cast_if_schema_valid(changeset, attrs) do
    changeset
    |> cast(attrs, [:schema_version])
    |> cast_embed(:study, required: true)
    |> cast_embed(:graphs, required: true)
    |> cast_embed(:simulation, required: true)
    |> cast_embed(:family, required: true)
    |> cast_embed(:pilot, required: true)
    |> cast_embed(:pilot_to_final, required: true)
    |> cast_embed(:final, required: true)
  end

  defp materialize(attrs) do
    changeset = changeset(%__MODULE__{}, attrs)

    case apply_action(changeset, :validate) do
      {:ok, definition} ->
        {:ok, definition}

      {:error, changeset} ->
        {:error,
         SchemaValidator.error_from_changeset(
           changeset,
           StudyError.invalid_json_value([])
         )}
    end
  end

  # Bounded traversal of the raw map, before any cast.
  #
  # A JSON object key must be a string of valid UTF-8. An invalid key is
  # rejected at the map that holds it, so no error path ever carries a value the
  # caller sent. A string value must be valid UTF-8 and is rejected at its own
  # field or list index.
  #
  # Depth and entry count are checked for one collection at a time. A map or a
  # list with too many entries is rejected at its own path, and a nested
  # collection starts its own count. Nothing accumulates across the document,
  # because D0 fixes the entry limit per collection.
  defp json_structure(value), do: json_structure(value, [], 1)

  defp json_structure(value, path, depth) when is_map(value) do
    with :ok <- within_structure_limits(map_size(value), depth, path) do
      reject_bad_key(value, path, depth)
    end
  end

  defp json_structure(value, path, depth) when is_list(value) do
    with :ok <- within_structure_limits(length(value), depth, path) do
      value
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {nested, index}, :ok ->
        continue_json(nested, path ++ [index], depth + 1)
      end)
    end
  end

  defp json_structure(value, path, _depth) when is_binary(value) do
    if String.valid?(value), do: :ok, else: {:error, invalid_value(path)}
  end

  defp json_structure(value, _path, _depth)
       when is_boolean(value) or is_number(value) or is_nil(value),
       do: :ok

  defp json_structure(_value, path, _depth), do: {:error, invalid_value(path)}

  defp continue_json(value, path, depth) do
    case json_structure(value, path, depth) do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp reject_bad_key(map, path, depth) do
    Enum.reduce_while(map, :ok, fn {key, nested}, :ok ->
      case json_key(key) do
        :ok -> continue_json(nested, path ++ [key], depth + 1)
        :error -> {:halt, {:error, StudyError.invalid_json_value(path)}}
      end
    end)
  end

  defp json_key(key) when is_binary(key), do: if(String.valid?(key), do: :ok, else: :error)
  defp json_key(_key), do: :error

  defp within_structure_limits(entries, depth, path) do
    cond do
      depth > @max_depth -> {:error, StudyError.structure_limit(path, @max_depth, depth)}
      entries > @max_entries -> {:error, StudyError.structure_limit(path, @max_entries, entries)}
      true -> :ok
    end
  end

  # A float-backed setting must reach Ecto as a representable float.
  defp representable_numbers(attrs) do
    case Enum.find(@float_paths, &unrepresentable?(&1, attrs)) do
      nil -> :ok
      path -> {:error, StudyError.unrepresentable_number(path)}
    end
  end

  defp unrepresentable?(path, attrs) do
    case fetch_path(attrs, path) do
      {:ok, number} when is_integer(number) -> not float_in_range?(number)
      _absent_or_float -> false
    end
  end

  defp fetch_path(value, []), do: {:ok, value}

  defp fetch_path(value, [key | rest]) when is_map(value) do
    case Map.fetch(value, key) do
      {:ok, nested} -> fetch_path(nested, rest)
      :error -> :error
    end
  end

  defp fetch_path(_value, _path), do: :error

  defp float_in_range?(number) do
    _ = :erlang.float(number)
    true
  rescue
    ArgumentError -> false
  end

  defp invalid_value(path), do: StudyError.invalid_json_value(path)

  defp encode(value), do: JsonBoundary.encode(value, &StudyError.invalid_json_value/1)

  defp within_limit(encoded),
    do: JsonBoundary.within_limit(encoded, @definition_limit, &too_large/1)

  defp too_large(limit),
    do: StudyError.too_large(limit, "The study definition exceeds the byte limit.")
end
