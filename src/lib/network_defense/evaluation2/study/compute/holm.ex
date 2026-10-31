defmodule NetworkDefense.Evaluation2.Study.Compute.Holm do
  @moduledoc false

  @doc "Apply inclusive Decimal Holm correction and restore canonical order."
  @spec correct([number()], number()) :: [map()]
  def correct(p_values, alpha) when is_list(p_values) and p_values != [] do
    unless valid_probability?(alpha) and Enum.all?(p_values, &valid_probability?/1) do
      raise ArgumentError, "Holm requires finite probabilities in [0, 1]"
    end

    Decimal.Context.with(%Decimal.Context{precision: 64}, fn ->
      correct_decimal(p_values, alpha)
    end)
  end

  def correct([], _alpha), do: []

  defp correct_decimal(p_values, alpha) do
    count = length(p_values)
    decimal_alpha = decimal(alpha)

    p_values
    |> Enum.with_index()
    |> Enum.sort_by(fn {p_value, position} -> {p_value, position} end)
    |> Enum.with_index()
    |> Enum.map_reduce(Decimal.new(0), fn {{p_value, position}, rank}, previous ->
      adjusted =
        p_value
        |> decimal()
        |> Decimal.mult(Decimal.new(count - rank))
        |> Decimal.max(previous)
        |> Decimal.min(Decimal.new(1))

      reject? = Decimal.compare(adjusted, decimal_alpha) != :gt
      emitted = consistent_float(adjusted, alpha, reject?)

      {{position, %{p_value: p_value, adjusted_p_value: emitted, reject?: reject?}}, adjusted}
    end)
    |> elem(0)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp consistent_float(adjusted, alpha, reject?) do
    # Decimal.to_float rejects subnormals that the VM can represent.
    {value, ""} = adjusted |> Decimal.to_string(:scientific) |> Float.parse()

    cond do
      reject? and value > alpha -> alpha * 1.0
      not reject? and value <= alpha -> next_float(alpha * 1.0)
      true -> value
    end
  end

  defp next_float(value) do
    <<bits::unsigned-64>> = <<value::float-64>>
    <<next::float-64>> = <<bits + 1::unsigned-64>>
    next
  end

  defp decimal(value) when is_integer(value), do: Decimal.new(value)
  defp decimal(value), do: Decimal.from_float(value)

  defp valid_probability?(value), do: is_number(value) and value >= 0 and value <= 1
end
