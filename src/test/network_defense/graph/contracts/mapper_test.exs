defmodule NetworkDefense.Graph.Contracts.MapperTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Graph.Contracts.Mapper

  test "CONTRACT-MAP-01: preserves input order" do
    assert {:ok, [2, 4, 6]} = Mapper.map([1, 2, 3], &{:ok, &1 * 2})
  end

  test "CONTRACT-MAP-02: preserves mapper failures and stops traversal" do
    parent = self()

    assert :error =
             Mapper.map([1, 2, 3], fn value ->
               send(parent, {:mapped, value})
               if value == 2, do: :error, else: {:ok, value}
             end)

    assert_received {:mapped, 1}
    assert_received {:mapped, 2}
    refute_received {:mapped, 3}

    assert {:error, :invalid} = Mapper.map([1], fn _value -> {:error, :invalid} end)
  end
end
