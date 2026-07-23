defmodule NetworkDefenseWeb.Contracts do
  @moduledoc false

  defmacro __using__(options) do
    quote do
      use NetworkDefense.Contracts, unquote(options)
    end
  end
end
