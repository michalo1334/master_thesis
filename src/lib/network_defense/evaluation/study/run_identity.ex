defmodule NetworkDefense.Evaluation.Study.RunIdentity do
  @moduledoc false

  alias NetworkDefense.Simulation.{Experiment, Run, Seed}

  @spec owned_by_experiment?(Run.t(), Experiment.t()) :: boolean()
  def owned_by_experiment?(%Run{} = run, %Experiment{} = experiment) do
    run.experiment_id == experiment.id and run.graph_revision_id == experiment.graph_revision_id
  end

  @spec derived_seed?(Run.t(), Experiment.t()) :: boolean()
  def derived_seed?(%Run{seed: seed, trial_index: index}, %Experiment{master_seed: master_seed}) do
    is_integer(seed) and is_integer(index) and is_integer(master_seed) and
      seed == Seed.child_seed(master_seed, index)
  end
end
