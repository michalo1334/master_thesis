defmodule NetworkDefense.Credo.GuardrailAst do
  @moduledoc false

  def nodes(ast), do: nodes(ast, [])
  def body_forms({:__block__, _, forms}), do: Enum.flat_map(forms, &body_forms/1)
  def body_forms(forms) when is_list(forms), do: Enum.flat_map(forms, &body_forms/1)
  def body_forms({:quote, _, _}), do: []
  def body_forms(form), do: [form]
  defp nodes({:quote, _, _}, acc), do: acc

  defp nodes({head, _, args} = node, acc) when is_list(args) do
    args |> Enum.reduce(nodes(head, [node | acc]), &nodes/2)
  end

  defp nodes(tuple, acc) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.reduce(acc, &nodes/2)
  end

  defp nodes(list, acc) when is_list(list), do: Enum.reduce(list, acc, &nodes/2)
  defp nodes(_, acc), do: acc

  def module_name({:__aliases__, _, parts}) when is_list(parts) do
    if Enum.all?(parts, &is_atom/1),
      do: parts |> Enum.map_join(".", &Atom.to_string/1) |> normalize_module(),
      else: nil
  end

  def module_name(atom) when is_atom(atom), do: atom |> Atom.to_string() |> normalize_module()
  def module_name(_), do: nil

  def alias_name({:__aliases__, _, parts}) when is_list(parts) do
    if Enum.all?(parts, &is_atom/1),
      do: parts |> Enum.map_join(".", &Atom.to_string/1) |> normalize_module(),
      else: nil
  end

  def alias_name(atom) when is_atom(atom), do: atom |> Atom.to_string() |> normalize_module()
  def alias_name(_), do: nil

  defp normalize_module("Elixir." <> name), do: name
  defp normalize_module(name), do: name

  def line({_, meta, _}) when is_list(meta), do: Keyword.get(meta, :line, 1)
  def line(_), do: 1

  def issue(context, check, message, node, exit_status \\ nil) do
    opts = [message: message, line_no: line(node)]
    opts = if exit_status, do: Keyword.put(opts, :exit_status, exit_status), else: opts
    Credo.Check.format_issue(context, opts, check)
  end
end
