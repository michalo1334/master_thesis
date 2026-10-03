defmodule NetworkDefense.Credo.RetiredProjectionTypeHelper do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check:
        "The root projection contract must not define retired type helpers; literal nesting is resolved without alias or macro expansion."
    ]

  alias NetworkDefense.Credo.GuardrailAst
  @root "NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection"
  @retired [:node_type, :relationship_type]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)

    GuardrailAst.modules(SourceFile.ast(source_file))
    |> Enum.flat_map(fn
      {name, _node, body} ->
        if name == @root do
          GuardrailAst.body_forms(body)
          |> Enum.flat_map(fn
            {:defp, _, [head | _]} = node ->
              {fun, args, meta} = function_head(head)

              if fun in @retired and is_list(args) and length(args) == 1 do
                [
                  format_issue(context,
                    message:
                      "Remove the retired private #{fun}/1 helper from the root projection contract; use the node or relationship registry.",
                    line_no: Keyword.get(meta, :line, GuardrailAst.line(node))
                  )
                ]
              else
                []
              end

            _ ->
              []
          end)
        else
          []
        end

      _ ->
        []
    end)
  end

  defp function_head({:when, _, [head | _]}), do: function_head(head)
  defp function_head({name, meta, args}), do: {name, args, meta}
  defp function_head(_), do: {nil, nil, []}
end
