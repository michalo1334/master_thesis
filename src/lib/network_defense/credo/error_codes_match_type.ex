defmodule NetworkDefense.Credo.ErrorCodesMatchType do
  use Credo.Check,
    base_priority: :high,
    category: :consistency,
    explanations: [
      check: "An Errors module's @type code must contain exactly the atoms returned by codes/0."
    ]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if Path.expand(source_file.filename) == Path.expand("lib/network_defense/errors.ex") do
      context = Context.build(source_file, params, __MODULE__)

      error_modules()
      |> Enum.flat_map(&issues_for(context, &1))
    else
      []
    end
  end

  defp error_modules do
    :network_defense
    |> Application.spec(:modules)
    |> Enum.filter(fn module ->
      Code.ensure_loaded?(module) and function_exported?(module, :codes, 0) and
        Module.split(module) |> List.last() == "Errors"
    end)
  end

  defp issues_for(context, module) do
    case code_atoms(module, MapSet.new()) do
      {:ok, type_codes} ->
        list_codes = MapSet.new(module.codes())

        if type_codes == list_codes do
          []
        else
          [mismatch_issue(context, module, type_codes, list_codes)]
        end

      {:error, reason} ->
        [format_issue(context, message: "#{inspect(module)} #{reason}.", line_no: 1)]
    end
  end

  defp code_atoms(module, visited) do
    if MapSet.member?(visited, module) do
      {:error, "has a cyclic @type code reference"}
    else
      with {:ok, type} <- code_type(module) do
        type_atoms(type, MapSet.put(visited, module))
      end
    end
  end

  defp code_type(module) do
    with {:ok, types} <- Code.Typespec.fetch_types(module),
         {:type, {:code, type, []}} <- Enum.find(types, &match?({:type, {:code, _, []}}, &1)) do
      {:ok, type}
    else
      _ -> {:error, "does not define @type code"}
    end
  end

  defp type_atoms({:atom, _, code}, _visited) when is_atom(code), do: {:ok, MapSet.new([code])}

  defp type_atoms({:type, _, :union, types}, visited) do
    Enum.reduce_while(types, {:ok, MapSet.new()}, fn type, {:ok, codes} ->
      case type_atoms(type, visited) do
        {:ok, type_codes} -> {:cont, {:ok, MapSet.union(codes, type_codes)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp type_atoms(
         {:remote_type, _, [{:atom, _, module}, {:atom, _, :code}, []]},
         visited
       ),
       do: code_atoms(module, visited)

  defp type_atoms(_type, _visited), do: {:error, "has an unsupported @type code member"}

  defp mismatch_issue(context, module, type_codes, list_codes) do
    only_in_type = MapSet.difference(type_codes, list_codes) |> MapSet.to_list() |> Enum.sort()
    only_in_list = MapSet.difference(list_codes, type_codes) |> MapSet.to_list() |> Enum.sort()

    format_issue(context,
      message:
        "#{inspect(module)} @type code differs from codes/0: " <>
          "typespec only #{inspect(only_in_type)}, codes only #{inspect(only_in_list)}.",
      line_no: 1
    )
  end
end
