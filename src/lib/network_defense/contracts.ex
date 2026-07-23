defmodule NetworkDefense.Contracts do
  @moduledoc false

  defmacro __using__(options) do
    dashboard? = Keyword.get(options, :dashboard, false)

    quote do
      use Ecto.Schema
      import Ecto.Changeset
      alias NetworkDefense.Contracts

      @primary_key false

      def __contract__, do: true
      def dashboard_contract?, do: unquote(dashboard?)
      def contract_meta, do: %{}
      defoverridable contract_meta: 0

      def validate(attrs) when is_map(attrs) do
        struct(__MODULE__)
        |> changeset(attrs)
        |> apply_action(:validate)
      end

      def to_wire(contract), do: Contracts.to_wire(contract)
      def to_params(contract), do: Contracts.to_params(contract)
    end
  end

  def to_wire(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.new(fn {key, value} -> {key, to_wire(value)} end)
  end

  def to_wire(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, to_wire(value)} end)

  def to_wire(list) when is_list(list), do: Enum.map(list, &to_wire/1)
  def to_wire(value), do: value

  def to_params(%_{} = struct), do: struct |> Map.from_struct() |> to_params()

  def to_params(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), to_params(value)} end)
  end

  def to_params(list) when is_list(list), do: Enum.map(list, &to_params/1)
  def to_params(value), do: value
end
