defmodule NetworkDefense.Repo.Migrations.EnsureMigratedSquash do
  use Ecto.Migration
  alias Ecto.Migration.SchemaMigration

  def up do
    needed_migrations =
      MapSet.new([
        20_260_710_195_300,
        20_260_710_195_428,
        20_260_710_195_625,
        20_260_717_000_001,
        20_260_717_120_000,
        20_260_717_130_000,
        20_260_718_120_000,
        20_260_719_200_000,
        20_260_719_200_001,
        20_260_719_200_002,
        20_260_719_200_003,
        20_260_719_200_004,
        20_260_723_120_000,
        20_260_726_120_000,
        20_260_726_130_000,
        20_260_728_120_000,
        20_260_729_120_000,
        20_260_731_180_000,
        20_260_801_000_000,
        20_260_801_000_100,
        20_260_801_000_200,
        20_260_802_000_000,
        20_260_802_000_100,
        20_260_802_000_200,
        20_260_802_000_300,
        20_260_802_000_400,
        20_260_809_000_000,
        20_260_814_211_315,
        20_260_817_010_000,
        20_260_824_000_000,
        20_260_830_000_000,
        20_260_831_000_000,
        20_260_901_000_000,
        20_260_902_000_000,
        20_260_903_000_000,
        20_260_904_000_000,
        20_260_905_000_000,
        20_260_906_000_000,
        20_260_907_000_000,
        20_260_908_000_000
      ])

    repo = NetworkDefense.Repo
    # XXX: No support for prefix yet.
    {migration_repo, query, all_opts} = SchemaMigration.versions(repo, repo.config(), nil)

    has_migrations =
      migration_repo.all(query, all_opts)
      |> MapSet.new()

    if needed_migrations != has_migrations do
      raise "Missing migrations: #{inspect(MapSet.difference(needed_migrations, has_migrations))}
extra migrations: #{inspect(MapSet.difference(has_migrations, needed_migrations))}"
    end
  end

  def down do
  end
end
