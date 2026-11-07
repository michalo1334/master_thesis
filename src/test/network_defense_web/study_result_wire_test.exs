defmodule NetworkDefenseWeb.StudyResultWireTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation2.Study.{
    Comparison,
    PilotOutcome,
    Result,
    Revision,
    Selection,
    Tier
  }

  alias NetworkDefense.Evaluation2.Study.Result.Comparison, as: ResultComparison

  alias NetworkDefense.Evaluation2.Study.Result.Comparison.{
    Adjustment,
    Assessment,
    Estimate,
    Interval,
    Statistics,
    Test
  }

  alias NetworkDefense.Evaluation2.Study.Result.Family
  alias NetworkDefense.Evaluation2.Study.Result.Timing
  alias NetworkDefense.Evaluation2.Study.Result.Timing.Replica
  alias NetworkDefense.Evaluation2.Study.Result.Timing.Tier, as: TimingTier
  alias NetworkDefenseWeb.StudyWire

  test "stored comparison values and all fifteen raw timing triplets survive the generated reply" do
    comparison = %ResultComparison{
      identity: %Comparison{
        tier: :small,
        budget: 3,
        alternative: :random,
        reference: :cvss,
        outcome: "mission_impact"
      },
      statistics: %Statistics{
        method: :matching_bounded_mean_v1,
        estimate: %Estimate{contrast: :alternative_minus_reference, value: -0.123456789123456},
        interval: %Interval{
          confidence_level: 0.95,
          lower: -0.876543210987654,
          upper: 0.023456789012345
        },
        test: %Test{
          method: :sign_conservative_betting,
          alternative: :two_sided,
          raw_p_value: 0.0000000123456789
        },
        assessment: %Assessment{status: :non_informative, warnings: [:empty_inversion]}
      },
      adjustment: %Adjustment{adjusted_p_value: 0.0000000370370367, reject_null: true}
    }

    timing = %Timing{
      by_tier:
        Map.new(Tier.all(), fn tier ->
          {tier,
           %TimingTier{
             replicas:
               Map.new(0..4, fn position ->
                 {position,
                  %Replica{
                    plan_selection_us: 1001 + position,
                    simulation_us: 2003 + position,
                    total_us: 3004 + 2 * position
                  }}
               end)
           }}
        end)
    }

    result = %Result{
      execution_id: Ecto.UUID.generate(),
      revision: %Revision{study_id: "wire-test", revision: 2},
      pilot_outcome: %PilotOutcome{outcome: :insufficient},
      selection: %Selection{candidate_id: "chosen", plan_count_per_side: 2, attacks_per_plan: 4},
      family: %Family{
        id: "declared-family",
        method: :holm,
        alpha: 0.05,
        comparisons: [comparison]
      },
      timing: timing
    }

    reply = StudyWire.validate_reply(%{status: "ok", result: StudyWire.result(result)})
    assert reply.status == "ok"
    [wire] = reply.result.comparisons
    assert wire.estimate == comparison.statistics.estimate.value
    assert wire.lower == comparison.statistics.interval.lower
    assert wire.upper == comparison.statistics.interval.upper
    assert wire.confidence_level == comparison.statistics.interval.confidence_level
    assert wire.raw_p_value == comparison.statistics.test.raw_p_value
    assert wire.adjusted_p_value == comparison.adjustment.adjusted_p_value
    assert wire.reject_null
    assert wire.warnings == ["empty_inversion"]
    assert wire.assessment == "non_informative"
    assert wire.test_method == "sign_conservative_betting"
    assert wire.test_alternative == "two_sided"
    assert wire.contrast == "alternative_minus_reference"
    assert reply.result.family_method == "holm"
    assert Enum.map(reply.result.timing, & &1.tier) == ["small", "medium", "large"]

    for {tier, wire_tier} <- Enum.zip(Tier.all(), reply.result.timing) do
      assert [_, _, _, _, _] = wire_tier.replicas

      for replica <- wire_tier.replicas do
        source = timing.by_tier[tier].replicas[replica.position]
        assert Map.drop(replica, [:position]) == Map.from_struct(source)
      end

      for summary <- wire_tier.summaries do
        assert summary.minimum_us <= summary.median_us
        assert summary.median_us <= summary.maximum_us
      end
    end
  end
end
