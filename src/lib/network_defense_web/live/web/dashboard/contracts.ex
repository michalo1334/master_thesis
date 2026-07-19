defmodule NetworkDefenseWeb.Web.Contracts do
  @moduledoc false

  defmacro __using__(_options) do
    quote do
      def __contract__, do: true
      def contract_meta, do: %{}
      defoverridable contract_meta: 0
    end
  end
end
