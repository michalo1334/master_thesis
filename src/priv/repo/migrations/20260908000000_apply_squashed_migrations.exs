defmodule NetworkDefense.Repo.Migrations.SquashMigrations do
  use Ecto.Migration

  def up do
    repo = NetworkDefense.Repo
    {:ok, _path} = repo.__adapter__.structure_load(__DIR__, repo.config())
  end
end
