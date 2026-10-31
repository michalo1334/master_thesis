# Smoke entrypoint for the Evaluation2 numerical kernel. This is NOT the Goal 06
# statistical protocol: it runs a few declared scenarios against the production
# kernel to prove the harness plumbing, and prints every limit next to the
# measured rates. Family error, protocol-dimension coverage, and Pilot selection
# performance belong to Goal 06.
#
#   MIX_ENV=test mix run --no-start scripts/evaluation2_statistical_check.exs --smoke
#   MIX_ENV=test mix run --no-start scripts/evaluation2_statistical_check.exs --dry-run
#
# One flag is required; a full-protocol run is rejected. `--no-start` keeps the
# application, both Ecto repositories, Gust, Oban, and the endpoint down. The
# runner starts `:nx` itself because Nx is a numeric library.

{:ok, _} = Application.ensure_all_started(:nx)

unless Code.ensure_loaded?(NetworkDefense.Evaluation2Test.NumericAnchors) do
  Code.require_file("../test/support/evaluation2_numeric_anchors.ex", __DIR__)
end

defmodule Evaluation2.SmokeCheck do
  alias NetworkDefense.Evaluation2.Study.Compute
  alias NetworkDefense.Evaluation2Test.NumericAnchors, as: Anchor
  # Declared before any result is read.
  @seed 20_261_030
  @confidence 0.95
  @nominal_rate 0.05
  @datasets 20
  @counts [{5, 10}, {20, 40}]
  @scenarios [
    {"rare-row null", :rare_rows, 0.0},
    {"mixed null", :mixed, 0.0},
    {"mixed known effect", :mixed, -0.1}
  ]
  @anchor_pairs [5, 20, 160]
  @pilot_outer_subsamples 8
  @pilot_guard_quantile 0.9
  @null_checks 4

  def main(argv) do
    mode = mode!(argv)

    if application_started?() or started?(NetworkDefense.Repo) or started?(Gust.Repo) do
      raise "run this entrypoint with mix run --no-start"
    end

    IO.puts(header(mode) <> metadata())

    case mode do
      :dry_run ->
        IO.puts("Nothing executed.")

      :smoke ->
        IO.puts("\n3. Bounded deterministic anchors\n" <> anchors())
        IO.puts("\n4. Declared crossed scenarios\n" <> scenarios())
        IO.puts("\n5. Pilot precision plumbing\n" <> pilot())
        IO.puts("\n6. Limits\n" <> limits())
    end
  end

  defp mode!(["--smoke"]), do: :smoke
  defp mode!(["--dry-run"]), do: :dry_run

  defp mode!(_argv) do
    raise ArgumentError,
          "use --smoke or --dry-run; this entrypoint does not run the declared protocol"
  end

  defp header(mode) do
    """
    ==========================================================================
    Evaluation2 numerical smoke check (#{mode})
    Kernel: #{inspect(Compute)} | seed #{@seed} | confidence #{@confidence}
    Scope: bounded smoke evidence only. Not a Goal 06 protocol result.
    ==========================================================================
    """
  end

  defp metadata do
    """
    1. Metadata and provenance
      elixir/otp: #{System.version()} / #{System.otp_release()}
      nx: #{app_version(:nx)} | backend: #{inspect(Nx.default_backend())} | decimal: #{app_version(:decimal)}
      application started: #{application_started?()}
      generator: Erlang exsss, SHA-256 streams by model/effect/shape/replicate/row-column role
      network_defense repo started: #{started?(NetworkDefense.Repo)}
      gust repo started: #{started?(Gust.Repo)}
      mix.lock sha256: #{digest("mix.lock")}
      kernel source sha256: #{kernel_digest()}
      git commit: #{git_commit()}

    2. Declared smoke plan
      counts: #{inspect(@counts)} | datasets per cell: #{@datasets} | kernel calls: #{planned_calls()}
      scenarios: #{Enum.map_join(@scenarios, ", ", &elem(&1, 0))}
      anchors: #{inspect(@anchor_pairs)} constant pairs, rare-event 5x10, 36-member Holm family
      Pilot call: #{@pilot_outer_subsamples} outer samples, guard #{@pilot_guard_quantile}
    """
  end

  defp planned_calls do
    length(@counts) * length(@scenarios) * @datasets + length(@anchor_pairs) + 1 +
      @pilot_outer_subsamples
  end

  defp app_version(app) do
    case Application.spec(app, :vsn) do
      nil -> "unavailable"
      vsn -> to_string(vsn)
    end
  end

  defp application_started?,
    do: Enum.any?(Application.started_applications(), &(elem(&1, 0) == :network_defense))

  defp started?(name), do: Process.whereis(name) != nil
  defp digest(path), do: path |> File.read() |> unwrap(&sha256/1)
  defp sha256(contents), do: Base.encode16(:crypto.hash(:sha256, contents), case: :lower)
  # Identity of the numerical source under test, so a report names the measured
  # code and not only the dependency lock.
  defp kernel_digest do
    [
      "lib/network_defense/evaluation2/study/compute.ex"
      | Path.wildcard("lib/network_defense/evaluation2/study/compute/*.ex")
    ]
    |> Enum.sort()
    |> Enum.map_join("\n", &File.read!/1)
    |> sha256()
  end

  defp git_commit do
    System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) |> unwrap(&String.trim/1)
  rescue
    _error -> "unavailable"
  end

  defp unwrap({:ok, value}, fun), do: fun.(value)
  defp unwrap({value, 0}, fun), do: fun.(value)
  defp unwrap(_error, _fun), do: "unavailable"

  defp anchors do
    constant = Enum.map(@anchor_pairs, &constant_anchor/1)
    Enum.join(constant ++ [rare_event_anchor(), holm_anchor()], "\n")
  end

  # The constant-contrast probes are the documented arithmetic anchors; the
  # independent reference reproduces them, so the kernel is checked against it.
  defp constant_anchor(pairs) do
    anchored = Anchor.constant_contrast(-0.1, 1.0, pairs, @confidence)
    {:ok, kernel} = Compute.compare(constant(pairs, 0.4, 0.5), inference())

    unless abs(kernel.p_value - anchored.p_value) <= anchored.p_value * 1.0e-9 do
      raise "constant anchor mismatch"
    end

    "  constant -0.1 contrast, #{pairs} pairs\n    p #{kernel.p_value} | anchor #{anchored.p_value} | " <>
      "agrees #{abs(kernel.p_value - anchored.p_value) <= anchored.p_value * 1.0e-9} | " <>
      "interval [#{Float.round(kernel.lower, 6)}, #{Float.round(kernel.upper, 6)}]"
  end

  defp constant(pairs, alternative, reference) do
    input(
      List.duplicate(List.duplicate(alternative, pairs), pairs),
      List.duplicate(List.duplicate(reference, pairs), pairs)
    )
  end

  defp rare_event_anchor do
    {:ok, kernel} =
      Compute.compare(
        input(
          List.duplicate(List.duplicate(0.0, 10), 5),
          List.duplicate(List.duplicate(0.1, 10), 5)
        ),
        inference()
      )

    width = kernel.upper - kernel.lower
    unless kernel.p_value == 1.0 and width > 1.0, do: raise("rare-event anchor mismatch")

    "  rare-event 5x10 contrast\n    p #{kernel.p_value} | width #{Float.round(width, 5)} | " <>
      "no point certainty #{kernel.p_value == 1.0 and width > 1.0}"
  end

  defp holm_anchor do
    anchored = Anchor.constant_contrast(-0.1, 1.0, 160, @confidence)
    [first | rest] = Compute.holm([anchored.p_value | List.duplicate(1.0, 35)], @nominal_rate)
    unless first.reject? and Enum.all?(rest, &(not &1.reject?)), do: raise("Holm anchor mismatch")

    "  36-member Holm family\n    first rejects #{first.reject?} | adjusted #{Float.round(first.adjusted_p_value, 6)} | " <>
      "any other rejects #{Enum.any?(rest, & &1.reject?)}"
  end

  defp scenarios do
    for {name, model, effect} <- @scenarios, {rows, columns} <- @counts do
      rejected = Enum.count(0..(@datasets - 1), &rejects?(model, effect, {rows, columns}, &1))
      {low, high} = wilson(rejected, @datasets)
      rate = rejected / @datasets
      tail_bound = :math.exp(-2 * @datasets * max(rate - @nominal_rate, 0.0) ** 2)

      flag =
        if effect == 0.0 and rate > @nominal_rate and tail_bound < 0.01 / @null_checks,
          do: " FLAG: Hoeffding diagnostic excess",
          else: ""

      "  #{name} #{inspect({rows, columns})}: rejected #{rejected}/#{@datasets} " <>
        "| Wilson [#{round4(low)}, #{round4(high)}]#{flag}"
    end
    |> Enum.join("\n")
  end

  defp rejects?(model, effect, {rows, columns}, replicate) do
    {alternative, reference} = dataset(model, effect, rows, columns, replicate)
    {:ok, result} = Compute.compare(input(alternative, reference), inference())
    result.p_value <= @nominal_rate
  end

  defp pilot do
    # The Pilot call uses the larger declared shape.
    {rows, columns} = Enum.max_by(@counts, fn {candidate_rows, _} -> candidate_rows end)
    alternative = Anchor.build(rows, columns, fn i, j -> 0.4 + 0.02 * rem(2 * i + 3 * j, 4) end)

    {:ok, result} =
      Compute.pilot_precision(
        input(alternative, Anchor.build(rows, columns, fn _, _ -> 0.5 end)),
        %{plans: rows - 1, attacks: columns - 1},
        %{outer_subsamples: @pilot_outer_subsamples, guard_quantile: @pilot_guard_quantile},
        inference(),
        @seed
      )

    "  #{inspect({rows - 1, columns - 1})}: #{length(result.half_widths)} outer samples, " <>
      "guarded half-width #{round4(result.guarded_half_width)} | informative #{result.informative}\n" <>
      "  Plumbing only: this smoke does not assess candidate selection or fan-in."
  end

  defp limits do
    """
      - #{length(@counts)} count pairs, #{@datasets} datasets per cell, #{length(@scenarios)} scenarios,
        #{@null_checks} true-null rate checks and two known-effect power checks.
      - Flag rule: one-sided Hoeffding bound exp(-2*n*max(rate-0.05,0)^2) < 0.01/J,
        J=#{@null_checks}, only for true-null rejection excess. Wilson intervals are descriptive.
      - Interval coverage, family error, and Pilot selection performance are not assessed here.
      - The complete protocol and its interpretation remain Goal 06 work.
    """
  end

  # Rare rows: independent Bernoulli plan rows against the matching constant.
  defp dataset(:rare_rows, _effect, rows, columns, replicate) do
    values =
      draws(
        rows,
        stream_seed(:rare_rows, 0.0, rows, columns, replicate, :rows),
        &if(&1 < 0.1, do: 1.0, else: 0.0)
      )

    {Enum.map(values, &List.duplicate(&1, columns)),
     List.duplicate(List.duplicate(0.1, columns), rows)}
  end

  # Mixed: bounded row, column, and interaction terms with a shared reference.
  defp dataset(:mixed, effect, rows, columns, replicate) do
    row_seed = stream_seed(:mixed, effect, rows, columns, replicate, :rows)
    column_seed = stream_seed(:mixed, effect, rows, columns, replicate, :columns)
    row_signs = draws(rows, row_seed, &if(&1 < 0.5, do: -1.0, else: 1.0))
    column_signs = draws(columns, column_seed, &if(&1 < 0.5, do: -1.0, else: 1.0))

    alternative =
      for row_sign <- row_signs do
        Enum.map(column_signs, &(0.5 + effect + 0.1 * row_sign + 0.1 * &1 + 0.1 * row_sign * &1))
      end

    {alternative, List.duplicate(Enum.map(column_signs, &(0.5 + 0.2 * &1)), rows)}
  end

  defp draws(count, seed, fun) do
    {values, _state} =
      Enum.map_reduce(1..count, :rand.seed_s(:exsss, seed), fn _index, state ->
        {value, state} = :rand.uniform_s(state)
        {fun.(value), state}
      end)

    values
  end

  # One declared stream per model, shape, and replicate: the seed is a hash of
  # those coordinates, so cells are independent and replayable.
  defp stream_seed(model, effect, rows, columns, replicate, role) do
    value =
      "#{@seed}|#{model}|#{effect}|#{rows}x#{columns}|#{replicate}|#{role}"
      |> then(&:crypto.hash(:sha256, &1))
      |> :binary.decode_unsigned()
      |> rem(4_000_000_000)

    {value, value + 7919, value + 104_729}
  end

  defp wilson(successes, datasets) do
    rate = successes / datasets
    z = 1.959963984540054
    z2 = z * z
    denominator = 1 + z2 / datasets
    centre = (rate + z2 / (2 * datasets)) / denominator

    spread =
      z * :math.sqrt(rate * (1 - rate) / datasets + z2 / (4 * datasets * datasets)) / denominator

    {max(centre - spread, 0.0), min(centre + spread, 1.0)}
  end

  defp input(alternative, reference),
    do: %{alternative: alternative, reference: reference, lower_bound: 0.0, upper_bound: 1.0}

  defp inference, do: %{confidence_level: @confidence}
  defp round4(value), do: Float.round(value, 4)
end

Evaluation2.SmokeCheck.main(System.argv())
