defmodule NetworkDefense.Evaluation.StudyConformance do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.Definition

  # Checked-in study definition examples.
  #
  # The JSON file is the normalized form. The YAML file is the form a caller
  # writes. Both must parse to one typed definition, and that definition must
  # encode back to the JSON file exactly.
  #
  # The helpers read and copy one checked-in definition. A path is a list of map
  # keys and list indexes, so a test changes one setting and nothing else.

  @root Path.expand("../../../contracts/evaluation/study/v1", __DIR__)
  @json_path Path.join(@root, "valid/study-small.json")
  @yaml_path Path.join(@root, "valid/study-small.yaml")

  @external_resource @json_path
  @external_resource @yaml_path

  @json @json_path |> File.read!() |> Jason.decode!()
  @yaml @yaml_path |> File.read!()

  def root, do: @root

  @doc "The normalized definition as a string-keyed JSON map."
  def definition, do: @json

  @doc "The same definition in YAML source form."
  def yaml, do: @yaml

  def read(relative_path),
    do: @root |> Path.join(relative_path) |> File.read!() |> Jason.decode!()

  @spec parsed!() :: Definition.t()
  def parsed!, do: assert_ok(Definition.parse(@json))

  @spec parse(map()) :: {:ok, Definition.t()} | {:error, struct()}
  def parse(attrs), do: Definition.parse(attrs)

  @spec parse_error(term()) :: struct()
  def parse_error(attrs) do
    case Definition.parse(attrs) do
      {:ok, definition} -> raise("expected a rejected definition, got: #{inspect(definition)}")
      {:error, error} -> error
    end
  end

  @doc "The fixture value at a path of map keys and list indexes."
  def fetch_definition(path), do: fetch_at_definition(@json, path)

  @doc "A copy of the fixture with one value replaced."
  def put_in_definition(path, value), do: put_in_definition(@json, path, value)

  @doc "A copy of a definition with one value replaced."
  def put_in_definition(definition, path, value) do
    {container_path, [last]} = Enum.split(path, -1)
    container(definition, container_path, fn parent -> put_child(parent, last, value) end)
  end

  @doc "A copy of the fixture with the value at a path replaced by a function."
  def update_definition(path, fun), do: update_definition(@json, path, fun)

  @doc "A copy of a definition with the value at a path replaced by a function."
  def update_definition(definition, path, fun) do
    {container_path, [last]} = Enum.split(path, -1)
    container(definition, container_path, fn parent -> update_child(parent, last, fun) end)
  end

  @doc "A copy of the fixture with one map key removed."
  def delete_key_definition(path) do
    {container_path, [key]} = Enum.split(path, -1)
    container(@json, container_path, &Map.delete(&1, key))
  end

  @doc "A copy of the fixture with one list entry removed."
  def delete_entry_definition(path) do
    {container_path, [index]} = Enum.split(path, -1)
    container(@json, container_path, &List.delete_at(&1, index))
  end

  @doc "A value at a path of map keys and list indexes."
  def fetch_at_definition(value, []), do: value

  def fetch_at_definition(map, [key | rest]) when is_map(map),
    do: fetch_at_definition(Map.fetch!(map, key), rest)

  def fetch_at_definition(list, [index | rest]) when is_list(list),
    do: fetch_at_definition(Enum.at(list, index), rest)

  # The container is the value that holds the last path segment.
  defp container(value, [], fun), do: fun.(value)

  defp container(map, [key | rest], fun) when is_map(map),
    do: Map.update!(map, key, &container(&1, rest, fun))

  defp container(list, [index | rest], fun) when is_list(list),
    do: List.update_at(list, index, &container(&1, rest, fun))

  defp put_child(container, key, value) when is_map(container), do: Map.put(container, key, value)

  defp put_child(container, index, value) when is_list(container),
    do: List.replace_at(container, index, value)

  defp update_child(container, key, fun) when is_map(container),
    do: Map.update!(container, key, fun)

  defp update_child(container, index, fun) when is_list(container),
    do: List.update_at(container, index, fun)

  defp assert_ok({:ok, value}), do: value
  defp assert_ok({:error, error}), do: raise("expected ok, got: #{inspect(error)}")
end
