defmodule NetworkDefense.Graph.Contracts.Mapper do
  @moduledoc false

  @spec map(Enumerable.t(), (term() -> {:ok, term()} | :error | {:error, term()})) ::
          {:ok, [term()]} | :error | {:error, term()}
  def map(values, mapper) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, mapped} ->
      case mapper.(value) do
        {:ok, contract} -> {:cont, {:ok, [contract | mapped]}}
        :error -> {:halt, :error}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, mapped} -> {:ok, Enum.reverse(mapped)}
      error -> error
    end
  end
end
