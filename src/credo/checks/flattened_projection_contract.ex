defmodule NetworkDefense.Credo.FlattenedProjectionContract do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check:
        "Projection declarations must use nested child modules, not flattened names; literal nesting is resolved, but aliases and macros are not expanded."
    ]

  alias NetworkDefense.Credo.GuardrailAst
  @root "NetworkDefenseWeb.Contracts.Dashboard.Graph.TopologyProjection"

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)

    GuardrailAst.modules(SourceFile.ast(source_file))
    |> Enum.flat_map(fn
      {name, node, _body} ->
        case name do
          value when is_binary(value) and value != @root ->
            if String.starts_with?(value, @root) and String.length(value) > String.length(@root) and
                 binary_part(value, String.length(@root), 1) != ".",
               do: [
                 GuardrailAst.issue(
                   context,
                   __MODULE__,
                   "Do not flatten a projection contract child into the #{inspect(@root)} namespace; declare a nested child module instead.",
                   node
                 )
               ],
               else: []

          _ ->
            []
        end

      _ ->
        []
    end)
  end
end
