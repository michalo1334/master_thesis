defmodule NetworkDefense.Credo.SuccessShapedExitCatch do
  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    explanations: [
      check:
        "Review exit catches that return success-shaped values; they can hide failed operations."
    ]

  alias NetworkDefense.Credo.GuardrailAst

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    context = Context.build(source_file, params, __MODULE__)

    GuardrailAst.nodes(SourceFile.ast(source_file))
    |> Enum.flat_map(fn
      {:try, _, [blocks]} ->
        report_catches(Keyword.get(blocks, :catch, []), context)

      {kind, _, [_head, clauses]} when kind in [:def, :defp, :defmacro, :defmacrop] ->
        report_catches(Keyword.get(clauses, :catch, []), context)

      _ ->
        []
    end)
  end

  defp report_catches(catches, context) do
    catches
    |> List.wrap()
    |> Enum.flat_map(fn
      {:->, _, [[:exit, _reason], body]} = clause ->
        if success_shape?(body) do
          [
            GuardrailAst.issue(
              context,
              __MODULE__,
              "Review this catch of :exit: returning a success-shaped value may hide operation failure.",
              clause,
              0
            )
          ]
        else
          []
        end

      _ ->
        []
    end)
  end

  defp success_shape?(:ok), do: true
  defp success_shape?(nil), do: true
  defp success_shape?([]), do: true
  defp success_shape?(map) when is_map(map) and map_size(map) == 0, do: true
  defp success_shape?({:%{}, _, []}), do: true
  defp success_shape?({:{}, _, [:ok, _]}), do: true
  defp success_shape?({:ok, _}), do: true
  defp success_shape?(_), do: false
end
