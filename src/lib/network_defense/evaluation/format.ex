defmodule NetworkDefense.Evaluation.Format do
  @moduledoc false

  # Shared console number formatting for evaluation command output.

  def number(value), do: value |> Kernel./(1) |> float_to_binary() |> trim_zeroes()

  def percent(value), do: "#{round(value * 100)}%"

  defp float_to_binary(value), do: :erlang.float_to_binary(value, decimals: 4)

  defp trim_zeroes(value), do: value |> String.trim_trailing("0") |> String.trim_trailing(".")
end
