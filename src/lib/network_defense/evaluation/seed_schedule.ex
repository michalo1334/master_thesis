defmodule NetworkDefense.Evaluation.SeedSchedule do
  @moduledoc """
  Named child-seed index ranges for the evaluation seed streams.

  All streams derive from the manifest's `evaluation.seed` root so that
  changing one stream never changes another:

    * index 0 - topology generation. The enterprise topology source uses its
      explicit `source.seed`; this range is the fallback for derived sources.
    * index 1 - reserved for derived selection streams.
    * index 2 - optimizer simulation. Derived from each strategy-run's declared
      selection seed,
      so changing a selection seed changes optimizer simulation but never
      attack seeds.
    * index 3 - attack evaluation. The shared master seed for every baseline
      and post-defense experiment.
  """

  alias NetworkDefense.Simulation.Seed

  @topology 0
  @optimizer_simulation 2
  @attack_evaluation 3

  @type t :: %{
          topology_seed: integer(),
          attack_evaluation_seed: integer(),
          entry_host_id: String.t(),
          optimizer_trials: pos_integer(),
          optimizer_iterations: pos_integer(),
          max_attempts: pos_integer()
        }

  @spec build(map(), String.t()) :: t()
  def build(manifest, entry_host_id) do
    %{
      topology_seed: topology_seed(manifest),
      attack_evaluation_seed: attack_evaluation_seed(manifest),
      entry_host_id: entry_host_id,
      optimizer_trials: optimizer_trials(manifest),
      optimizer_iterations: optimizer_iterations(manifest),
      max_attempts: get_in(manifest, ["attacker", "max_attempts"])
    }
  end

  defp optimizer_trials(manifest) do
    get_in(manifest, ["evaluation", "optimizer_trials"]) ||
      get_in(manifest, ["evaluation", "trials"])
  end

  defp optimizer_iterations(manifest) do
    get_in(manifest, ["evaluation", "optimizer_iterations"]) || 1
  end

  @spec topology_seed(map()) :: integer()
  def topology_seed(manifest) do
    get_in(manifest, ["source", "seed"]) || Seed.child_seed(evaluation_seed(manifest), @topology)
  end

  @spec optimizer_simulation_seed(integer()) :: integer()
  def optimizer_simulation_seed(selection_seed),
    do: Seed.child_seed(selection_seed, @optimizer_simulation)

  @spec attack_evaluation_seed(map()) :: integer()
  def attack_evaluation_seed(manifest),
    do: Seed.child_seed(evaluation_seed(manifest), @attack_evaluation)

  defp evaluation_seed(manifest), do: get_in(manifest, ["evaluation", "seed"])
end
