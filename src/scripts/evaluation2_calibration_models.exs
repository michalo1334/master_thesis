# Deterministic crossed-data generators for the prespecified calibration
# protocol (`docs/inprogress/evaluation2-statistical-checks.md`, sections 2 and 4).
#
# Equations are implemented literally. Every outcome stays inside the declared
# model range [0, 1]. No generator clips, rescales, or reorders a matrix, because
# the matching cover must see the frozen logical order.
#
# Streams: one SHA-256 derivation per (purpose, scenario identity, shape,
# replicate, input role). Row inputs and shared column inputs use separate
# roles, so the two input collections stay independent, as the observation
# model requires. Replicates of different cells never share a stream.

defmodule Evaluation2.CalibrationModels do
  @moduledoc """
  Declared bounded-outcome generators of the calibration protocol.

  The grid models are the fixed equations of the protocol: deterministic, rare
  plan rows, attack-only, shared-column cancellation, pure interaction, and
  mixed effects. The family and planning generators add the six-comparison and
  two-comparison families with a shared reference.

  Every function is pure and replayable from `seed/0`. A repeated call with the
  same arguments returns the same matrices, which the runner relies on for
  reproducible streams and for the Pilot/Final separation (the phase string is
  part of the stream identity).
  """

  alias NetworkDefense.Evaluation2.Study.Randomness

  # Declared validation seed; fixed before any result was inspected.
  @seed 20_261_030

  # Family-behaviour effects: three false nulls, then three true nulls.
  @family_effects [-0.1, 0.1, -0.1, 0.0, 0.0, 0.0]
  @family_true_null_positions [3, 4, 5]
  @family_false_null_positions [0, 1, 2]

  # Planning families use one negative and one positive effect.
  @planning_effects [-0.1, 0.1]

  @doc "Declared validation seed."
  def seed, do: @seed

  @doc "Family effects in comparison order."
  def family_effects, do: @family_effects

  @doc "Comparison positions of the true nulls in a partial-null family."
  def family_true_null_positions, do: @family_true_null_positions

  @doc "Comparison positions of the false nulls in a partial-null family."
  def family_false_null_positions, do: @family_false_null_positions

  @doc "Planning-family effects in comparison order."
  def planning_effects, do: @planning_effects

  ## Grid models

  @doc """
  One independent dataset of a grid scenario at a declared shape.

  Returns the aligned `{alternative, reference}` matrices of one replicate.
  """
  def dataset(%{name: name, model: model} = scenario, shape, replicate) do
    context = grid_context(name, shape, replicate)

    case model do
      :deterministic -> deterministic(scenario, shape)
      :rare_rows -> rare_rows(scenario, shape, context)
      :attack_only -> attack_only(scenario, shape, context)
      :cancellation -> cancellation(shape, context)
      :interaction -> interaction(scenario, shape, context)
      :mixed -> mixed(scenario, shape, context)
    end
  end

  # C = 0.5, A = 0.5 + d: equal constants at d = 0, unequal constants otherwise.
  defp deterministic(%{d: d}, {rows, columns}) do
    {constant(rows, columns, 0.5 + d), constant(rows, columns, 0.5)}
  end

  # A = Z_i with Z_i ~ Bernoulli(p) repeated across columns, C = p. True contrast 0.
  defp rare_rows(%{p: p}, {rows, columns}, context) do
    values = draws(rows, context ++ [:rows], fn uniform -> if uniform < p, do: 1.0, else: 0.0 end)
    {Enum.map(values, &List.duplicate(&1, columns)), constant(rows, columns, p)}
  end

  # A = 0.5 + d + 0.2 V_j, C = 0.5. True contrast d.
  defp attack_only(%{d: d}, {rows, columns}, context) do
    signs = rademacher(columns, context ++ [:columns])
    alternative = List.duplicate(Enum.map(signs, &(0.5 + d + 0.2 * &1)), rows)
    {alternative, constant(rows, columns, 0.5)}
  end

  # A = C = 0.5 + 0.25 V_j: both sides respond identically. True contrast 0.
  defp cancellation({rows, columns}, context) do
    signs = rademacher(columns, context ++ [:columns])
    side = List.duplicate(Enum.map(signs, &(0.5 + 0.25 * &1)), rows)
    {side, side}
  end

  # A = 0.5 + d + 0.2 R_i V_j, C = 0.5. True contrast d.
  defp interaction(%{d: d}, {rows, columns}, context) do
    row_signs = rademacher(rows, context ++ [:rows])
    column_signs = rademacher(columns, context ++ [:columns])

    alternative =
      Enum.map(row_signs, fn r ->
        Enum.map(column_signs, &(0.5 + d + 0.2 * r * &1))
      end)

    {alternative, constant(rows, columns, 0.5)}
  end

  # A = 0.5 + d + 0.1 R_i + b V_j + 0.1 R_i V_j, C = 0.5 + 0.2 V_j. True contrast d.
  defp mixed(%{d: d, b: b}, {rows, columns}, context) do
    row_signs = rademacher(rows, context ++ [:rows])
    column_signs = rademacher(columns, context ++ [:columns])

    alternative =
      Enum.map(row_signs, fn r ->
        Enum.map(column_signs, &(0.5 + d + 0.1 * r + b * &1 + 0.1 * r * &1))
      end)

    reference = List.duplicate(Enum.map(column_signs, &(0.5 + 0.2 * &1)), rows)
    {alternative, reference}
  end

  ## Six-comparison family

  @doc """
  Six aligned comparisons of one synthetic family.

  Row and column inputs are shared across the six comparisons, and every
  comparison uses the same shared reference `C = 0.5 + 0.2 V_j`. The row
  coefficient alternates in sign, the column coefficient is `+0.1`, and the
  interaction coefficient is `0.1`.

  `null_case` is `:global_null` (all effects zero) or `:partial_null`
  (`[-0.1, 0.1, -0.1, 0, 0, 0]`).
  """
  def family(model, null_case, shape, replicate) do
    context = family_context(model, null_case, shape, replicate)
    effects = if null_case == :global_null, do: List.duplicate(0.0, 6), else: @family_effects

    case model do
      :deterministic ->
        {rows, columns} = shape

        for effect <- effects do
          {constant(rows, columns, 0.5 + effect), constant(rows, columns, 0.5)}
        end

      :mixed ->
        {rows, columns} = shape
        row_signs = rademacher(rows, context ++ [:rows])
        column_signs = rademacher(columns, context ++ [:columns])
        reference = List.duplicate(Enum.map(column_signs, &(0.5 + 0.2 * &1)), rows)

        for {effect, position} <- Enum.with_index(effects) do
          row_coefficient = row_coefficient(position)

          alternative = mixed_matrix(row_signs, column_signs, effect, row_coefficient)

          {alternative, reference}
        end
    end
  end

  ## Pilot planning family

  @doc """
  Two aligned comparisons of one planning family at a pool shape and phase.

  `kind` is `:deterministic` (`A = 0.5 + d`, `C = 0.5`) or `:mixed`
  (`A = 0.5 + d + 0.1 R_i + 0.1 V_j + 0.1 R_i V_j`, `C = 0.5 + 0.2 V_j`).
  Effects are `[-0.1, 0.1]`. The two comparisons share one reference, matching
  the shared-reference cost assumption.

  `phase` is `:pilot` or `:final`. The phase is part of the stream identity, so
  fresh Final data never replays Pilot observations.
  """
  def planning_family(kind, shape, repetition, phase, pool_shape) do
    context = planning_context(kind, pool_shape, repetition, phase)
    {rows, columns} = shape

    case kind do
      :deterministic ->
        for effect <- @planning_effects do
          {constant(rows, columns, 0.5 + effect), constant(rows, columns, 0.5)}
        end

      :mixed ->
        row_signs = rademacher(rows, context ++ [:rows])
        column_signs = rademacher(columns, context ++ [:columns])
        reference = List.duplicate(Enum.map(column_signs, &(0.5 + 0.2 * &1)), rows)

        for effect <- @planning_effects do
          alternative = mixed_matrix(row_signs, column_signs, effect, 0.1)

          {alternative, reference}
        end
    end
  end

  @doc """
  Planning stream identity of one comparison.

  The same identity is passed to every declared candidate, which reproduces the
  shared-permutation-prefix rule of the Pilot policy.
  """
  def planning_seed(kind, pool_shape, repetition, comparison) do
    Randomness.root(
      @seed,
      planning_context(kind, pool_shape, repetition, :pilot) ++ [:planning, comparison]
    )
  end

  defp row_coefficient(position), do: if(rem(position, 2) == 0, do: 0.1, else: -0.1)

  defp mixed_matrix(row_signs, column_signs, effect, row_coefficient) do
    Enum.map(row_signs, fn row ->
      Enum.map(column_signs, &(0.5 + effect + row_coefficient * row + 0.1 * &1 + 0.1 * row * &1))
    end)
  end

  ## Shared helpers

  @doc "Constant matrix of one declared shape."
  def constant(rows, columns, value),
    do: List.duplicate(List.duplicate(value, columns), rows)

  @doc "Independent Rademacher signs from one declared stream."
  def rademacher(count, context),
    do: draws(count, context, fn uniform -> if uniform < 0.5, do: -1.0, else: 1.0 end)

  defp draws(count, context, fun) do
    {values, _state} =
      Enum.map_reduce(1..count, rng(context), fn _index, state ->
        {uniform, state} = :rand.uniform_s(state)
        {fun.(uniform), state}
      end)

    values
  end

  # Independent full-width roots avoid the collisions caused by reducing every
  # stream into a four-billion-value seed space.
  defp rng(context), do: :rand.seed_s(:exsss, stream_seed(context))

  defp stream_seed(context) do
    List.to_tuple(
      for coordinate <- 0..2, do: Randomness.root(@seed, context ++ ["exsss", coordinate])
    )
  end

  @doc "Check the actual PRNG states for all declared stream contexts before generating outcomes."
  def audit_streams(scenarios, counts, datasets, family_shapes, family_reps, pools, planning_reps) do
    grid =
      for scenario <- scenarios,
          shape <- counts,
          replicate <- 0..(datasets - 1),
          role <- [:rows, :columns],
          do: grid_context(scenario.name, shape, replicate) ++ [role]

    families =
      for model <- [:deterministic, :mixed],
          null_case <- [:global_null, :partial_null],
          shape <- family_shapes,
          replicate <- 0..(family_reps - 1),
          role <- [:rows, :columns],
          do: family_context(model, null_case, shape, replicate) ++ [role]

    planning =
      for kind <- [:deterministic, :mixed],
          pool <- pools,
          repetition <- 0..(planning_reps - 1),
          phase <- [:pilot, :final],
          role <- [:rows, :columns],
          do: planning_context(kind, pool, repetition, phase) ++ [role]

    contexts = grid ++ families ++ planning
    identities = Enum.map(contexts, fn context -> :rand.export_seed_s(rng(context)) end)
    unique = MapSet.size(MapSet.new(identities))
    unless unique == length(contexts), do: raise("declared calibration PRNG stream collision")

    %{
      contexts: length(contexts),
      unique_prng_states: unique,
      collision_free: true,
      includes_unused_role_superset: true
    }
  end

  defp grid_context(name, {rows, columns}, replicate),
    do: ["calibration", "grid", name, "#{rows}x#{columns}", replicate]

  defp family_context(model, null_case, {rows, columns}, replicate),
    do: ["calibration", "family", model, null_case, "#{rows}x#{columns}", replicate]

  defp planning_context(kind, {rows, columns}, repetition, phase),
    do: ["calibration", "planning", kind, "#{rows}x#{columns}", repetition, phase]
end
