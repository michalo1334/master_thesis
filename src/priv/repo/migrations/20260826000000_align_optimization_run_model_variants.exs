defmodule NetworkDefense.Repo.Migrations.AlignOptimizationRunModelVariants do
  use Ecto.Migration

  def change do
    drop constraint(:optimization_runs, :optimization_runs_model_variant_valid)

    create constraint(:optimization_runs, :optimization_runs_model_variant_valid,
             check:
               "model_variant IS NULL OR model_variant IN ('full', 'blast_only_unconstrained', 'mission_only', 'blast_only', 'mission_only_unconstrained', 'full_unconstrained')"
           )
  end
end
