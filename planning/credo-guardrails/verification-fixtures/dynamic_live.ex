defmodule Fixture.DynamicLive do
  alias Repo

  def load(module), do: apply(module, :get, [Fixture.Record, 1])
  def unqualified, do: Repo.get(Fixture.Record, 1)

  defmacro alias_dynamic(module) do
    quote do
      alias unquote(module)
    end
  end
end
