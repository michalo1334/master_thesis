defmodule NetworkDefense.Evaluation2.Study.Randomness do
  @moduledoc false

  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Simulation.Seed

  @modulus 9_223_372_036_854_775_807
  @contract "evaluation2-sha256-json-v1"
  def contract, do: @contract
  def modulus, do: @modulus

  def root(seed, context) do
    :crypto.hash(:sha256, Jason.encode!([@contract, seed, context]))
    |> :binary.decode_unsigned()
    |> rem(@modulus)
  end

  def selection_seed(%{seed: seed}, phase, row),
    do: root(seed, ["selection", to_string(phase), row])

  def evaluation_root(%{seed: seed}, phase, tier),
    do: root(seed, ["evaluation", to_string(phase), to_string(tier)])

  def pilot_planning_seed(%{seed: seed}, comparison) do
    root(seed, [
      "planning",
      "pilot",
      comparison.tier,
      comparison.budget,
      to_string(comparison.alternative),
      "cvss",
      "mission_impact"
    ])
  end

  def outer_seed(definition, comparison, outer, role) do
    root(pilot_planning_seed(definition, comparison), ["outer", outer, to_string(role)])
  end

  # Check distinct logical streams once, including the downstream attack schedule.
  def validate(definition) do
    pilot = Definition.pilot_capacity(definition)
    final = Enum.max_by(definition.pilot.candidates, & &1.plans).plans

    rows =
      for {phase, count} <- [{:pilot, pilot.plans}, {:final, final}],
          row <- 0..(count - 1),
          do: selection_seed(definition, phase, row)

    roots =
      for phase <- [:pilot, :final],
          tier <- definition.tiers,
          do: evaluation_root(definition, phase, tier.tier)

    planning = Enum.map(Definition.comparisons(definition), &pilot_planning_seed(definition, &1))
    final_attacks = Enum.max_by(definition.pilot.candidates, & &1.attacks).attacks

    columns =
      for {phase, count} <- [{:pilot, pilot.attacks}, {:final, final_attacks}],
          tier <- definition.tiers,
          index <- 1..count,
          do: Seed.child_seed(evaluation_root(definition, phase, tier.tier), index)

    values = rows ++ roots ++ planning ++ columns
    if length(values) == MapSet.size(MapSet.new(values)), do: :ok, else: {:error, :seed_collision}
  end
end
