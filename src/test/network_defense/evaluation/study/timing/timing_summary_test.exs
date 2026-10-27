defmodule NetworkDefense.Evaluation.Study.Timing.TimingSummaryTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.Final.Contracts.Request, as: FinalRequest
  alias NetworkDefense.Evaluation.{FinalConformance, StudyFixtures}

  alias NetworkDefense.Evaluation.Study.{
    CompactResult,
    FinalSelection,
    PilotOutcome
  }

  alias NetworkDefense.Evaluation.Study.CompactResult.{
    AnalysisReference,
    CollectionReference,
    PilotAnalysisReference
  }

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError

  alias NetworkDefense.Evaluation.Study.Timing.{
    DurationSummary,
    Interval,
    ReplicaTiming,
    TierTiming,
    TimingSummary
  }

  @duration %{values_us: [39, 47, 41, 44, 42], median_us: 42, minimum_us: 39, maximum_us: 47}

  @phase_id "11111111-1111-4111-8111-111111111111"
  @execution_id "22222222-2222-4222-8222-222222222222"
  @snapshot_id "33333333-3333-4333-8333-333333333333"

  describe "DurationSummary.summarize/1" do
    test "T5-01: WHEN five measured values are supplied in positions 0..4, THE duration summary SHALL preserve position order and report the median, minimum, and maximum" do
      assert {:ok, %DurationSummary{} = summary} = DurationSummary.summarize([10, 20, 30, 40, 50])

      assert summary.values_us == [10, 20, 30, 40, 50]
      assert summary.median_us == 30
      assert summary.minimum_us == 10
      assert summary.maximum_us == 50
    end

    test "T5-02: WHEN the five values are not numerically sorted, THE duration summary SHALL take the median from a sorted copy and SHALL not reorder values_us" do
      assert {:ok, %DurationSummary{} = summary} = DurationSummary.summarize([39, 47, 41, 44, 42])

      assert summary.values_us == [39, 47, 41, 44, 42]
      assert summary.median_us == 42
      assert summary.minimum_us == 39
      assert summary.maximum_us == 47
    end

    test "T5-03: WHEN a duration list does not hold exactly five values, THE duration summary SHALL reject it" do
      for values <- [[], [1], [1, 2, 3, 4], [1, 2, 3, 4, 5, 6], :not_a_list, nil] do
        assert DurationSummary.summarize(values) == {:error, incomplete()}
      end
    end

    test "T5-04: WHEN a duration value is negative or is not an integer, THE duration summary SHALL reject it" do
      for values <- [
            [-1, 2, 3, 4, 5],
            [1, 2, 3, 4, 5.0],
            [1, 2, 3, 4, "5"],
            [1, 2, nil, 4, 5]
          ] do
        assert DurationSummary.summarize(values) == {:error, incomplete()}
      end
    end
  end

  describe "DurationSummary.changeset/2" do
    test "T5-10: WHEN stored duration values agree with the measured values, THE duration summary changeset SHALL accept them" do
      assert %Ecto.Changeset{valid?: true} =
               DurationSummary.changeset(%DurationSummary{}, @duration)
    end

    test "T5-10: WHEN stored duration values are missing or disagree with the measured values, THE duration summary changeset SHALL reject them" do
      invalid = [
        Map.delete(@duration, :values_us),
        Map.delete(@duration, :median_us),
        Map.delete(@duration, :minimum_us),
        Map.delete(@duration, :maximum_us),
        %{@duration | values_us: [39, 47, 41, 44]},
        %{@duration | values_us: [39, 47, 41, 44, -5]},
        %{@duration | median_us: 41},
        %{@duration | minimum_us: 41},
        %{@duration | maximum_us: 50},
        %{@duration | minimum_us: -1},
        %{@duration | maximum_us: -1}
      ]

      for attrs <- invalid do
        assert %Ecto.Changeset{valid?: false} =
                 DurationSummary.changeset(%DurationSummary{}, attrs)
      end
    end
  end

  describe "TierTiming.summarize/3" do
    test "T5-05: WHEN five ReplicaTiming values hold positions 0..4 and one tier identity, THE tier summary SHALL summarize plan selection, simulation, and total durations" do
      timings =
        replica_timings("core", %{
          plan_selection: [39, 47, 41, 44, 42],
          simulation: [1_300, 1_100, 1_400, 1_200, 1_250],
          total: [4_000, 3_900, 4_200, 3_800, 4_100]
        })

      assert {:ok, %TierTiming{} = summary} = TierTiming.summarize("core", 0, timings)

      assert summary.tier == "core"
      assert summary.tier_position == 0

      assert %DurationSummary{} = summary.plan_selection
      assert summary.plan_selection.values_us == [39, 47, 41, 44, 42]
      assert summary.plan_selection.median_us == 42
      assert summary.plan_selection.minimum_us == 39
      assert summary.plan_selection.maximum_us == 47

      assert summary.simulation.values_us == [1_300, 1_100, 1_400, 1_200, 1_250]
      assert summary.simulation.median_us == 1_250
      assert summary.simulation.minimum_us == 1_100
      assert summary.simulation.maximum_us == 1_400

      assert summary.total.values_us == [4_000, 3_900, 4_200, 3_800, 4_100]
      assert summary.total.median_us == 4_000
      assert summary.total.minimum_us == 3_800
      assert summary.total.maximum_us == 4_200
    end

    test "T5-05: WHEN the total duration differs from the sum of the other two, THE tier summary SHALL keep the accepted total value" do
      timings =
        replica_timings("core", %{
          plan_selection: [10, 10, 10, 10, 10],
          simulation: [20, 20, 20, 20, 20],
          total: [900, 900, 900, 900, 901]
        })

      assert {:ok, summary} = TierTiming.summarize("core", 0, timings)
      assert summary.total.values_us == [900, 900, 900, 900, 901]
      assert summary.total.median_us == 900
      assert summary.total.maximum_us == 901
    end

    test "T5-06: WHEN the replica positions or the tier identities differ, THE tier summary SHALL reject the timings" do
      timings =
        replica_timings("core", %{
          plan_selection: [10, 20, 30, 40, 50],
          simulation: [10, 20, 30, 40, 50],
          total: [10, 20, 30, 40, 50]
        })

      invalid = [
        {"edge", 0, timings},
        {"core", 0, Enum.take(timings, 4)},
        {"core", 0, [List.first(timings) | Enum.take(timings, 4)]},
        {"core", 0, Enum.reverse(timings)},
        {"core", 0, replace(timings, 2, %{Enum.at(timings, 2) | position: 9})},
        {"core", 0, [:not_a_timing | Enum.take(timings, 4)]},
        {"core", 0, replace(timings, 0, %{Enum.at(timings, 0) | total: %{elapsed_us: -1}})},
        {"core", 0, replace(timings, 0, %{Enum.at(timings, 0) | simulation: :invalid})},
        {"core", 0, :not_a_list}
      ]

      for {tier, position, value} <- invalid do
        assert TierTiming.summarize(tier, position, value) == {:error, incomplete()}
      end
    end
  end

  describe "TierTiming.changeset/2" do
    test "WHEN the tier identity and all three duration summaries are present, THE tier summary changeset SHALL accept them" do
      assert %Ecto.Changeset{valid?: true} =
               TierTiming.changeset(%TierTiming{}, %{
                 tier: "core",
                 tier_position: 0,
                 plan_selection: @duration,
                 simulation: @duration,
                 total: @duration
               })
    end

    test "WHEN the tier identity or a duration summary is missing or invalid, THE tier summary changeset SHALL reject it" do
      params = %{
        tier: "core",
        tier_position: 0,
        plan_selection: @duration,
        simulation: @duration,
        total: @duration
      }

      invalid = [
        Map.delete(params, :tier),
        Map.delete(params, :tier_position),
        Map.delete(params, :plan_selection),
        Map.delete(params, :simulation),
        Map.delete(params, :total),
        %{params | tier: " "},
        %{params | tier_position: -1},
        %{params | total: %{@duration | median_us: 0}}
      ]

      for attrs <- invalid do
        assert %Ecto.Changeset{valid?: false} = TierTiming.changeset(%TierTiming{}, attrs)
      end
    end
  end

  describe "TimingSummary.summarize/2" do
    test "T5-07: WHEN timing values exist for every declared tier, THE timing summary SHALL follow the declared tier order and hold contiguous positions" do
      family = %{
        "edge" => %{tier_position: 0, timings: uniform_timings("edge", 900)},
        "core" => %{tier_position: 1, timings: uniform_timings("core", 100)}
      }

      # Declared order differs from the map key order.
      assert {:ok, %TimingSummary{tiers: tiers}} =
               TimingSummary.summarize(["edge", "core"], family)

      assert Enum.map(tiers, & &1.tier) == ["edge", "core"]
      assert Enum.map(tiers, & &1.tier_position) == [0, 1]

      assert Enum.map(tiers, & &1.plan_selection.values_us) == [
               [900, 900, 900, 900, 900],
               [100, 100, 100, 100, 100]
             ]
    end

    test "T5-08: WHEN a declared tier is missing, extra, duplicated, or out of order, THE timing summary SHALL reject the family" do
      family = %{
        "core" => %{tier_position: 0, timings: uniform_timings("core", 100)},
        "edge" => %{tier_position: 1, timings: uniform_timings("edge", 900)}
      }

      invalid = [
        {["core"], family},
        {["core", "edge", "extra"], family},
        {["core", "core"], family},
        {["core", "edge"], Map.delete(family, "edge")},
        {["core", "edge"], Map.put(family, "extra", %{tier_position: 2, timings: []})},
        {["core", "edge"],
         %{family | "edge" => %{tier_position: 0, timings: uniform_timings("edge", 900)}}},
        {["core", "edge"],
         %{family | "core" => %{tier_position: 1, timings: uniform_timings("core", 100)}}},
        {["core", "edge"], %{family | "core" => %{tier_position: 0, timings: []}}},
        {[], family},
        {[""], family},
        {:not_a_list, family},
        {["core", "edge"], :not_a_map}
      ]

      for {tiers, value} <- invalid do
        assert TimingSummary.summarize(tiers, value) == {:error, incomplete()}
      end
    end
  end

  describe "TimingSummary.validate_declared_order/2" do
    setup do
      family = %{
        "core" => %{tier_position: 0, timings: uniform_timings("core", 100)},
        "edge" => %{tier_position: 1, timings: uniform_timings("edge", 900)}
      }

      {:ok, summary} = TimingSummary.summarize(["core", "edge"], family)
      %{summary: summary}
    end

    test "WHEN the summary matches the declared tier order, THE order validation SHALL accept it",
         %{
           summary: summary
         } do
      assert TimingSummary.validate_declared_order(summary, ["core", "edge"]) == :ok
    end

    test "WHEN the summary differs from the declared tier order, THE order validation SHALL reject it",
         %{
           summary: summary
         } do
      assert TimingSummary.validate_declared_order(summary, ["edge", "core"]) ==
               {:error, incomplete()}

      assert TimingSummary.validate_declared_order(summary, ["core"]) == {:error, incomplete()}

      assert TimingSummary.validate_declared_order(summary, ["core", "edge", "extra"]) ==
               {:error, incomplete()}

      assert TimingSummary.validate_declared_order(%TimingSummary{tiers: []}, ["core"]) ==
               {:error, incomplete()}

      assert TimingSummary.validate_declared_order(:not_a_summary, ["core"]) ==
               {:error, incomplete()}
    end

    test "T5-08: WHEN a later tier item is not a tier summary, THE order validation SHALL return a bounded error instead of raising",
         %{
           summary: summary
         } do
      [core, _edge] = summary.tiers

      for malformed <- [nil, :not_a_tier, "edge", %{}, %TierTiming{}] do
        assert TimingSummary.validate_declared_order(
                 %TimingSummary{tiers: [core, malformed]},
                 ["core", "edge"]
               ) == {:error, incomplete()}
      end

      assert TimingSummary.validate_declared_order(
               %TimingSummary{tiers: [core, nil, %TierTiming{tier: "extra"}]},
               ["core", "edge", "extra"]
             ) == {:error, incomplete()}
    end
  end

  describe "TimingSummary.changeset/2" do
    test "WHEN every tier holds contiguous positions in list order, THE timing summary changeset SHALL accept it" do
      params = %{
        tiers: [
          tier_params("core", 0, @duration),
          tier_params("edge", 1, @duration)
        ]
      }

      assert %Ecto.Changeset{valid?: true} = TimingSummary.changeset(%TimingSummary{}, params)
    end

    test "WHEN the tier list is empty, gapped, duplicated, renamed twice, or unordered, THE timing summary changeset SHALL reject it" do
      invalid = [
        %{tiers: []},
        %{},
        %{
          tiers: [
            tier_params("core", 0, @duration),
            tier_params("edge", 2, @duration)
          ]
        },
        %{
          tiers: [
            tier_params("core", 0, @duration),
            tier_params("edge", 0, @duration)
          ]
        },
        %{
          tiers: [
            tier_params("core", 0, @duration),
            tier_params("core", 1, @duration)
          ]
        },
        %{
          tiers: [
            tier_params("core", 1, @duration),
            tier_params("edge", 0, @duration)
          ]
        },
        %{tiers: [tier_params("core", 0, @duration), %{tier: "edge", tier_position: 1}]},
        %{tiers: [tier_params("core", 0, @duration), nil]}
      ]

      for attrs <- invalid do
        assert %Ecto.Changeset{valid?: false} = TimingSummary.changeset(%TimingSummary{}, attrs)
      end
    end
  end

  # The strict compact-result parser owns unknown-field rejection through
  # `CompactResult.exact_fields?/2`; the timing changesets own value validation.
  # These cases need no database.
  describe "CompactResult.parse/1 timing payload" do
    test "T5-11: WHEN a schema-version-one result holds timing null, THE compact-result parser SHALL accept it" do
      assert {:ok, %CompactResult{timing: nil}} =
               compact_params() |> Map.put("timing", nil) |> CompactResult.parse()
    end

    test "T5-09: WHEN the timing payload holds an unknown field, THE strict parser SHALL reject it at every level" do
      params = compact_params()

      invalid_payloads = [
        put_in(params, ["timing", "extra"], true),
        put_in(params, ["timing", "tiers", Access.at(0), "extra"], true),
        put_in(params, ["timing", "tiers", Access.at(0), "plan_selection", "extra"], true)
      ]

      assert_rejected(invalid_payloads)
    end

    test "T5-09: WHEN the timing payload holds an invalid shape, THE strict parser SHALL reject it" do
      params = compact_params()

      invalid_payloads = [
        Map.put(params, "timing", "not-a-summary"),
        Map.put(params, "timing", [%{"tier" => "core", "tier_position" => 0}]),
        Map.put(params, "timing", %{}),
        put_in(params, ["timing", "tiers"], :not_a_list),
        put_in(params, ["timing", "tiers", Access.at(0)], "not-a-tier"),
        put_in(params, ["timing", "tiers", Access.at(0), "plan_selection"], []),
        put_in(params, ["timing", "tiers"], [List.first(params["timing"]["tiers"]), nil])
      ]

      assert_rejected(invalid_payloads)
    end

    test "T5-10: WHEN the timing payload holds values that contradict the stored statistics, THE strict parser SHALL reject it" do
      params = compact_params()
      plan = ["timing", "tiers", Access.at(0), "plan_selection"]

      invalid_payloads = [
        put_in(params, plan ++ ["values_us"], [100, 101, 102, 103]),
        put_in(params, plan ++ ["values_us"], [100, 101, 102, 103, -1]),
        put_in(params, plan ++ ["median_us"], 0),
        put_in(params, plan ++ ["minimum_us"], 1),
        put_in(params, plan ++ ["maximum_us"], 999),
        update_in(params, plan, &Map.delete(&1, "median_us"))
      ]

      assert_rejected(invalid_payloads)
    end

    test "T5-08: WHEN the timing payload holds duplicated, gapped, or unordered tiers, THE strict parser SHALL reject it" do
      params = compact_params()
      [first, second | _rest] = params["timing"]["tiers"]

      invalid_payloads = [
        put_in(params, ["timing", "tiers"], [first, %{second | "tier" => first["tier"]}]),
        put_in(params, ["timing", "tiers"], [first, %{second | "tier_position" => 7}]),
        put_in(params, ["timing", "tiers"], [second, first])
      ]

      assert_rejected(invalid_payloads)
    end

    test "T5-09: WHEN a required CompactResult embed is null, THE strict parser SHALL still reject it" do
      params = compact_params()

      for field <- [
            "pilot_collection",
            "pilot_analysis",
            "selection",
            "final_collection",
            "final_analysis",
            "final_result",
            "revision_assertions"
          ] do
        assert_rejected([Map.put(params, field, nil)])
      end

      assert {:ok, %CompactResult{timing: nil}} =
               params |> Map.put("timing", nil) |> CompactResult.parse()
    end
  end

  defp assert_rejected(payloads) do
    for payload <- payloads do
      assert {:error, error} = CompactResult.parse(payload)
      assert error == StudyError.final_result_invalid()
    end
  end

  # One complete compact payload whose only variable part is the timing summary.
  # Built from checked-in conformance examples, so it needs no database.
  defp compact_params(timing \\ nil) do
    definition = StudyFixtures.final_conformance_definition!()
    {:ok, request} = FinalRequest.parse(FinalConformance.request())

    %CompactResult{
      study_revision_id: FinalConformance.request()["study_revision_id"],
      execution_id: @execution_id,
      pilot_collection: collection_reference([801]),
      pilot_analysis: %PilotAnalysisReference{
        phase_id: @phase_id,
        gust_run_id: 802,
        outcome: pilot_outcome()
      },
      selection: %FinalSelection{
        candidate_id: "medium",
        plan_count_per_side: 4,
        attacks_per_plan: 4,
        pilot_override: false
      },
      final_collection: collection_reference([902, 903]),
      final_analysis: %AnalysisReference{phase_id: @phase_id, gust_run_id: 904},
      final_result: FinalConformance.result!(request),
      revision_assertions: definition.study.revisions,
      timing: timing || declared_timing(definition)
    }
    |> CompactResult.to_params()
  end

  defp collection_reference(gust_run_ids) do
    %CollectionReference{
      phase_id: @phase_id,
      gust_run_ids: gust_run_ids,
      snapshot_id: @snapshot_id
    }
  end

  defp pilot_outcome do
    {:ok, outcome} =
      PilotOutcome.parse(%{
        "outcome" => "recommended",
        "candidate_id" => "medium",
        "plan_count_per_side" => 4,
        "attacks_per_plan" => 4
      })

    outcome
  end

  defp declared_timing(definition) do
    tiers = definition.family.comparisons |> Enum.map(& &1.tier) |> Enum.uniq()

    family =
      tiers
      |> Enum.with_index()
      |> Map.new(fn {tier, tier_position} ->
        {tier, %{tier_position: tier_position, timings: uniform_timings(tier, 100)}}
      end)

    {:ok, summary} = TimingSummary.summarize(tiers, family)
    summary
  end

  defp incomplete, do: StudyError.final_timing_incomplete()

  defp replica_timings(tier, durations) do
    Enum.map(0..4, fn position ->
      {:ok, timing} =
        ReplicaTiming.new(%{
          tier: tier,
          position: position,
          plan_selection: %Interval{elapsed_us: Enum.at(durations.plan_selection, position)},
          simulation: %Interval{elapsed_us: Enum.at(durations.simulation, position)},
          total: %Interval{elapsed_us: Enum.at(durations.total, position)}
        })

      timing
    end)
  end

  defp uniform_timings(tier, elapsed_us) do
    replica_timings(tier, %{
      plan_selection: List.duplicate(elapsed_us, 5),
      simulation: List.duplicate(elapsed_us, 5),
      total: List.duplicate(elapsed_us, 5)
    })
  end

  defp tier_params(tier, tier_position, duration) do
    %{
      tier: tier,
      tier_position: tier_position,
      plan_selection: duration,
      simulation: duration,
      total: duration
    }
  end

  defp replace(list, index, value), do: List.replace_at(list, index, value)
end
