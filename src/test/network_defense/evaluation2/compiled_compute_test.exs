defmodule NetworkDefense.Evaluation2.CompiledComputeTest do
  use ExUnit.Case, async: false

  @moduletag :unit
  @moduletag case_id: "NUM-05"

  alias NetworkDefense.Evaluation2.Study.Compute
  alias NetworkDefense.Evaluation2.Study.Compute.{Input, Kernel}
  alias NetworkDefense.Evaluation2Test.NumericAnchors, as: Anchor

  test "WHEN CPU compilation is used THEN inference agrees with independent scalar arithmetic" do
    for {rows, columns} <- [{5, 10}, {10, 5}, {20, 40}], confidence <- [0.8, 0.95, 0.99] do
      alternative = Anchor.build(rows, columns, fn i, j -> 0.4 + 0.1 * rem(i + j, 3) end)
      reference = Anchor.build(rows, columns, fn _, j -> 0.5 + 0.1 * rem(j, 2) end)

      input = %{
        alternative: alternative,
        reference: reference,
        lower_bound: 0.0,
        upper_bound: 1.0
      }

      expected = Anchor.reference_compare(alternative, reference, 0.0, 1.0, confidence)
      assert {:ok, actual} = Compute.compare(input, %{confidence_level: confidence})
      assert_in_delta actual.lower, expected.lower, 1.0e-9
      assert_in_delta actual.upper, expected.upper, 1.0e-9
      assert_in_delta actual.p_value, expected.p_value, 1.0e-10
    end
  end

  test "WHEN interval endpoints are reported THEN independent capitals bracket each threshold" do
    input = %{
      alternative: List.duplicate(List.duplicate(0.4, 40), 20),
      reference: List.duplicate(List.duplicate(0.5, 40), 20),
      lower_bound: 0.0,
      upper_bound: 1.0
    }

    assert {:ok, result} = Compute.compare(input, %{confidence_level: 0.95})
    lower = (result.lower + 1.0) / 2.0
    upper = (result.upper + 1.0) / 2.0
    step = :math.pow(2.0, -34)
    matchings = [List.duplicate(0.45, 20)]
    threshold = :math.log(2.0 / (1.0 - 0.95))
    assert elem(Anchor.log_mean_capitals(matchings, lower, 1.0 - 0.95), 0) >= threshold - 1.0e-12

    assert elem(Anchor.log_mean_capitals(matchings, lower + step, 1.0 - 0.95), 0) <=
             threshold + 1.0e-12

    assert elem(Anchor.log_mean_capitals(matchings, upper, 1.0 - 0.95), 1) >= threshold - 1.0e-12

    assert elem(Anchor.log_mean_capitals(matchings, upper - step, 1.0 - 0.95), 1) <=
             threshold + 1.0e-12

    assert step <= 1.0e-10
  end

  test "WHEN a fused kernel runs THEN CPU and evaluator retain the same outer brackets and capitals" do
    for {rows, columns} <- [{1, 3}, {5, 10}, {10, 5}, {20, 40}] do
      input = %{
        alternative: Anchor.build(rows, columns, fn i, j -> 0.2 + 0.1 * rem(i + j, 5) end),
        reference: Anchor.build(rows, columns, fn _, j -> 0.4 + 0.1 * rem(j, 2) end),
        lower_bound: 0.0,
        upper_bound: 1.0
      }

      assert {:ok, prepared} = Input.prepare(input)
      error = Nx.tensor(0.05, type: :f64)

      expected =
        Nx.Defn.jit_apply(&Kernel.analyze/2, [prepared.matchings, error],
          compiler: Nx.Defn.Evaluator
        )

      actual =
        Nx.Defn.jit_apply(&Kernel.analyze/2, [prepared.matchings, error],
          compiler: EXLA,
          client: :host
        )

      Enum.zip(Tuple.to_list(expected), Tuple.to_list(actual))
      |> Enum.each(fn {left, right} ->
        assert_in_delta Nx.to_number(left), Nx.to_number(right), 1.0e-9
      end)
    end
  end
end
