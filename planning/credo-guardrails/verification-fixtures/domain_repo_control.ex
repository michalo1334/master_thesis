defmodule Fixture.Domain do
  def load, do: NetworkDefense.Repo.get(Fixture.Record, 1)
end
