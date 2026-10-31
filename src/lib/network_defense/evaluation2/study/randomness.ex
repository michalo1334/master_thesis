defmodule NetworkDefense.Evaluation2.Study.Randomness do
  @moduledoc """
  Versioned scientific seed derivation from one master seed.

  Canonical ordered JSON role contexts feed SHA-256 roots modulo `2^63 - 1`.
  Selection rows share phase/row inputs across strategies, budgets and tiers.
  Evaluation roots depend on phase/tier; simulation child seeds retain one-based
  trial indices. Pilot planning binds complete comparison identity and shared
  candidate permutation prefixes. Final inference uses no resampling stream.

  Scientific contexts exclude database IDs, timing replicas, process identity
  and scheduling. Collision checks distinguish logical streams; deterministic
  seed distinctness does not prove statistical independence.
  """

  alias NetworkDefense.Evaluation2.Study.Definition
  alias NetworkDefense.Simulation.Seed

  @modulus 9_223_372_036_854_775_807
  @contract "evaluation2-sha256-json-v1"
  @doc "Return the frozen seed-derivation contract identity."
  def contract, do: @contract
  @doc "Return the exclusive upper bound for master seeds and derived roots."
  def modulus, do: @modulus

  @doc "Derive a bounded root from a seed and an ordered primitive role context."
  def root(seed, context) do
    :crypto.hash(:sha256, Jason.encode!([@contract, seed, context]))
    |> :binary.decode_unsigned()
    |> rem(@modulus)
  end

  @doc "Derive one phase/row selection input, shared across physical groups."
  def selection_seed(%{seed: seed}, phase, row),
    do: root(seed, ["selection", to_string(phase), row])

  @doc "Derive one phase/tier root for aligned attack columns."
  def evaluation_root(%{seed: seed}, phase, tier),
    do: root(seed, ["evaluation", to_string(phase), to_string(tier)])

  @doc "Bind Pilot planning to complete comparison identity, including budget."
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

  @doc "Derive the shared-candidate row or column permutation root of one outer sample."
  def outer_seed(definition, comparison, outer, role) do
    root(pilot_planning_seed(definition, comparison), ["outer", outer, to_string(role)])
  end

  # Check distinct logical streams once, including the downstream attack schedule.
  @doc "Reject collisions among distinct declared streams and downstream attack seeds."
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

    comparisons = Definition.comparisons(definition)
    planning = Enum.map(comparisons, &pilot_planning_seed(definition, &1))

    outer =
      for comparison <- comparisons,
          index <- 0..(definition.pilot.precision.outer_subsamples - 1),
          role <- [:rows, :columns],
          do: outer_seed(definition, comparison, index, role)

    final_attacks = Enum.max_by(definition.pilot.candidates, & &1.attacks).attacks

    columns =
      for {phase, count} <- [{:pilot, pilot.attacks}, {:final, final_attacks}],
          tier <- definition.tiers,
          index <- 1..count,
          do: Seed.child_seed(evaluation_root(definition, phase, tier.tier), index)

    values = rows ++ roots ++ planning ++ outer ++ columns
    if length(values) == MapSet.size(MapSet.new(values)), do: :ok, else: {:error, :seed_collision}
  end
end
