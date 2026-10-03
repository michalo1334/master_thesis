defmodule NetworkDefense.Credo.LiveViewRepoDependency do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: "LiveView modules must call domain APIs instead of depending on the project Repo."
    ]

  alias NetworkDefense.Credo.GuardrailAst
  @repo "NetworkDefense.Repo"

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    if String.contains?(Path.expand(source_file.filename), "/lib/network_defense_web/live/") do
      context = Context.build(source_file, params, __MODULE__)

      GuardrailAst.nodes(SourceFile.ast(source_file))
      |> Enum.flat_map(fn node ->
        if forbidden_repo_reference?(node) do
          [
            GuardrailAst.issue(
              context,
              __MODULE__,
              "LiveView code must not depend directly on NetworkDefense.Repo; call a domain API instead.",
              node
            )
          ]
        else
          []
        end
      end)
      |> Enum.uniq_by(& &1.line_no)
    else
      []
    end
  end

  defp forbidden_repo_reference?(node) do
    direct_repo?(node) or grouped_repo?(node)
  end

  defp direct_repo?(node), do: GuardrailAst.alias_name(node) == @repo

  defp grouped_repo?({{:., _, [module, :{}]}, _, members}) when is_list(members) do
    GuardrailAst.module_name(module) == "NetworkDefense" and
      Enum.any?(members, &(GuardrailAst.alias_name(&1) == "Repo"))
  end

  defp grouped_repo?(_), do: false
end
