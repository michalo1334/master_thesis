defmodule Fixture.Live do
  def load, do: Elixir.NetworkDefense.Repo.get(Fixture.Record, 1)
end
