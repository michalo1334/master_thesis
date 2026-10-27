defmodule NetworkDefense.Evaluation.Study.Timing.Environment do
  @moduledoc false

  @type error :: :missing_environment | :environment_mismatch

  @spec matches(String.t() | nil, String.t() | nil) :: :ok | {:error, error()}
  def matches(declared, observed) do
    with {:ok, declared} <- present(declared),
         {:ok, observed} <- present(observed) do
      if declared == observed, do: :ok, else: {:error, :environment_mismatch}
    end
  end

  defp present(value) when is_binary(value) do
    if String.trim(value) == "", do: {:error, :missing_environment}, else: {:ok, value}
  end

  defp present(_value), do: {:error, :missing_environment}
end
