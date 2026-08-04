defmodule NetworkDefense.Repo.Migrations.DiscardBlockReachabilityOptimizations do
  use Ecto.Migration

  def up do
    execute("""
    DELETE FROM optimization_runs
    WHERE id IN (
      SELECT DISTINCT optimization_run_id
      FROM optimization_actions
      WHERE action_type = 'BlockReachability'
    )
    """)
  end

  def down do
    raise "discards optimization runs that used the retired BlockReachability action"
  end
end
