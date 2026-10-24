defmodule NetworkDefense.Evaluation.Study.Yaml do
  @moduledoc false

  alias NetworkDefense.Evaluation.JsonBoundary
  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  # The only YAML entry point for study definitions.
  #
  # The wrapper owns YAML syntax: one parse call with default options, then one
  # bounded JSON-compatible map or one bounded error. It keeps default string
  # keys, so document content never becomes an atom. It stores and logs no
  # document content, and it repeats no parser diagnostic.
  #
  # An error repeats no document value. Its path holds only caller key names or
  # list indexes that passed the string and UTF-8 checks, plus the fixed
  # `["yaml"]` marker. The shared envelope bounds the message text, not the path
  # length, so a path can name a caller field of up to the document byte limit.
  #
  # The limits are operational parser limits from decision D0. They are fixed
  # here on purpose: no environment value, no runtime default, and no scientific
  # meaning.

  @max_document_bytes 1_048_576
  @max_normalized_bytes 1_048_576
  @max_depth 32
  @max_entries 10_000

  @spec parse(term()) :: {:ok, map()} | {:error, StudyError.t()}
  def parse(document) when is_binary(document) do
    with :ok <- check_document_size(document),
         {:ok, value} <- read(document),
         :ok <- check_root(value),
         :ok <- check_bounds(value, [], 1),
         :ok <- check_json_compatible(value),
         :ok <- check_normalized_size(value) do
      {:ok, value}
    end
  end

  def parse(_document),
    do: {:error, StudyError.invalid_yaml(["yaml"], "The YAML document must be a binary string.")}

  defp check_document_size(document) do
    JsonBoundary.within_limit(document, @max_document_bytes, fn limit ->
      StudyError.too_large(limit, "The YAML document exceeds the byte limit.")
    end)
  end

  defp read(document) do
    case YamlElixir.read_from_string(document) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, malformed()}
    end
  rescue
    _exception -> {:error, malformed()}
  catch
    _kind, _reason -> {:error, malformed()}
  end

  defp malformed,
    do: StudyError.invalid_yaml(["yaml"], "The YAML document is not valid YAML.")

  defp check_root(value) when is_map(value), do: :ok

  defp check_root(_value),
    do: {:error, StudyError.invalid_yaml(["yaml"], "The YAML document root must be a mapping.")}

  # A scalar sits at depth 0. A root collection sits at depth 1, so a document
  # with 32 nested collections is accepted and one with 33 is rejected.
  #
  # A key joins the path only after it passes the string and UTF-8 checks, so no
  # path holds bytes that JSON cannot encode. The same check covers scalar
  # values at their own path. Bounds therefore stay ahead of the recursive JSON
  # traversal and still report a path that always encodes.
  defp check_bounds(value, path, _depth) when is_binary(value) do
    if String.valid?(value), do: :ok, else: {:error, StudyError.invalid_json_value(path)}
  end

  defp check_bounds(value, _path, _depth)
       when is_boolean(value) or is_number(value) or is_nil(value),
       do: :ok

  defp check_bounds(value, path, depth) when is_map(value) do
    with :ok <- check_depth(path, depth),
         :ok <- check_entries(map_size(value), path),
         :ok <- check_keys(value, path) do
      value
      |> Enum.sort_by(fn {key, _nested} -> key end)
      |> Enum.reduce_while(:ok, fn {key, nested}, :ok ->
        descend(nested, path ++ [key], depth)
      end)
    end
  end

  defp check_bounds(value, path, depth) when is_list(value) do
    with :ok <- check_depth(path, depth),
         :ok <- check_entries(length(value), path) do
      value
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {nested, index}, :ok ->
        descend(nested, path ++ [index], depth)
      end)
    end
  end

  defp check_bounds(_value, _path, _depth), do: :ok

  defp descend(nested, path, depth) do
    case check_bounds(nested, path, depth + 1) do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp check_depth(path, depth) when depth > @max_depth,
    do: {:error, StudyError.depth_exceeded(path, @max_depth, depth)}

  defp check_depth(_path, _depth), do: :ok

  defp check_keys(value, path) do
    Enum.reduce_while(value, :ok, fn {key, _nested}, :ok ->
      if is_binary(key) and String.valid?(key) do
        {:cont, :ok}
      else
        {:halt, {:error, StudyError.invalid_json_value(path)}}
      end
    end)
  end

  defp check_entries(entries, path) when entries > @max_entries,
    do: {:error, StudyError.entry_limit_exceeded(path, @max_entries, entries)}

  defp check_entries(_entries, _path), do: :ok

  defp check_json_compatible(value),
    do: JsonBoundary.string_keys_only(value, [], &StudyError.invalid_json_value/1)

  defp check_normalized_size(value) do
    with {:ok, encoded} <- JsonBoundary.encode(value, &StudyError.invalid_json_value/1) do
      JsonBoundary.within_limit(encoded, @max_normalized_bytes, fn limit ->
        StudyError.too_large(limit, "The normalized study definition exceeds the byte limit.")
      end)
    end
  end
end
