defmodule NetworkDefense.Credo.InlineContractTypeMapping do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    explanations: [
      check:
        "Review repeated inline atom-to-string mappings; a registry may own this contract mapping."
    ]

  alias NetworkDefense.Credo.GuardrailAst
  @retired [:node_type, :relationship_type]
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)

    GuardrailAst.modules(SourceFile.ast(source_file))
    |> Enum.flat_map(fn
      {name, _node, body} ->
        if String.starts_with?(name || "", "NetworkDefenseWeb.Contracts.") do
          body
          |> GuardrailAst.body_forms()
          |> Enum.filter(&mapping_clause?/1)
          |> Enum.reject(fn {_, _, [head | _]} = clause ->
            name == "NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection" and
              elem(function_head(head), 0) in @retired and match?({:defp, _, _}, clause)
          end)
          |> Enum.group_by(fn {_, _, [head | _]} ->
            {name, args} = function_head(head)
            {name, length(args)}
          end)
          |> Enum.flat_map(fn {{name, 1}, clauses} ->
            if length(clauses) >= 3 do
              [
                GuardrailAst.issue(
                  context,
                  __MODULE__,
                  "Review private #{name}/1: three or more clauses map literal atoms to literal strings; consider a contract registry.",
                  Enum.min_by(clauses, &GuardrailAst.line/1)
                )
              ]
            else
              []
            end
          end)
        else
          []
        end

      _ ->
        []
    end)
  end

  defp mapping_clause?({:defp, _, [head, body]}) do
    {_, args} = function_head(head)
    is_list(args) and length(args) == 1 and literal_atom?(hd(args)) and atom_string_pair?(body)
  end

  defp mapping_clause?(_), do: false
  defp function_head({:when, _, [head | _]}), do: function_head(head)
  defp function_head({name, _, args}) when is_atom(name) and is_list(args), do: {name, args}
  defp function_head(_), do: {nil, []}
  defp literal_atom?(atom) when is_atom(atom) and not is_nil(atom), do: true
  defp literal_atom?(_), do: false
  defp atom_string_pair?(do: value) when is_binary(value), do: true
  defp atom_string_pair?(value) when is_binary(value), do: true
  defp atom_string_pair?(_), do: false
end
