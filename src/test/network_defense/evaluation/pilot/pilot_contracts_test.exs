defmodule NetworkDefense.Evaluation.Pilot.PilotContractsTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.Evaluation.Pilot.CanonicalJson

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    CandidateComparisonRequest,
    CandidateComparisonResult,
    EvidenceSnapshotInput,
    PilotError,
    PilotRequest,
    PilotResult,
    Recommendation,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.Pilot.Assembler
  alias NetworkDefense.Evaluation.Pilot.Contracts.CandidateSummary
  alias NetworkDefense.Evaluation.Pilot.Limits
  alias NetworkDefense.Evaluation.Pilot.Work
  alias NetworkDefense.Evaluation.PilotConformance

  setup do
    original = Application.get_env(:network_defense, Limits)
    on_exit(fn -> restore_limits(original) end)
    :ok
  end

  describe "PILOT-01: valid snapshot document" do
    test "parses every comparison and computes the canonical byte count" do
      input = PilotConformance.snapshot_input!()

      assert input.phase == "pilot"
      assert input.schema_version == 1
      assert input.family_id == "family-example"
      assert Enum.count(input.payload.comparisons) == 2
      assert input.payload.evidence_role == "pilot"

      assert {:ok, bytes} =
               CanonicalJson.byte_size(SnapshotPayload.to_params(input.payload))

      assert input.payload_bytes == bytes
      assert bytes > 0
    end

    test "the stored result parses against the same request and payload" do
      result = PilotConformance.parsed_result!()

      assert result.outcome == "recommended"
      assert result.recommendation.plan_count == 6
      assert result.recommendation.attacks_per_plan == 10
      assert result.insufficient_reason == nil
      assert Enum.count(result.candidate_results) == 8
      assert Enum.count(result.candidate_summaries) == 4
    end

    test "every candidate request and candidate response conforms" do
      requests = PilotConformance.candidate_requests()
      responses = PilotConformance.candidate_responses()

      assert Enum.count(requests) == 8
      assert Enum.count(responses) == 8

      Enum.zip(requests, responses)
      |> Enum.each(fn {request, response} ->
        assert {:ok, %CandidateComparisonRequest{}} =
                 CandidateComparisonRequest.parse(request)

        assert {:ok, %CandidateComparisonRequest{} = parsed_request} =
                 CandidateComparisonRequest.parse(request)

        assert {:ok, %CandidateComparisonResult{}} =
                 CandidateComparisonResult.parse(response, parsed_request)
      end)
    end
  end

  describe "PILOT-02: snapshot rejection" do
    test "a declared comparison that is absent from the snapshot is reported" do
      input = PilotConformance.snapshot_input!()
      attrs = PilotConformance.read("invalid/missing-comparison.request.json")
      request = elem(PilotRequest.parse(attrs), 1)

      snapshot = %EvidenceSnapshot{
        id: Ecto.UUID.dump!(request.snapshot_id),
        study_revision_id: Ecto.UUID.dump!(request.study_revision_id),
        phase: :pilot,
        schema_version: 1,
        family_id: request.family_id,
        payload: SnapshotPayload.to_params(input.payload),
        payload_bytes: input.payload_bytes
      }

      assert {:error, %PilotError{code: "validation_failed", issues: issues}} =
               PilotRequest.matches_snapshot(request, snapshot, input.payload)

      codes = Enum.map(issues, & &1["code"])
      assert "missing_comparison" in codes
      assert "unexpected_comparison" in codes
    end

    test "a duplicate comparison is reported" do
      attrs = PilotConformance.read("invalid/duplicate-comparison.snapshot.json")

      assert {:error, %PilotError{code: "validation_failed", issues: issues}} =
               EvidenceSnapshotInput.parse(attrs)

      assert Enum.any?(issues, &(&1["code"] == "duplicate_comparison"))
    end

    test "a final phase is rejected at the public creation path" do
      attrs = Map.put(PilotConformance.snapshot(), "phase", "final")

      assert {:error, %PilotError{schema_errors: [_ | _]}} =
               EvidenceSnapshotInput.parse(attrs)
    end

    test "a final evidence role is rejected inside the payload" do
      attrs = PilotConformance.snapshot()
      attrs = put_in(attrs, ["payload", "evidence_role"], "final")

      assert {:error, %PilotError{schema_errors: [_ | _]}} =
               EvidenceSnapshotInput.parse(attrs)
    end

    test "a non-consecutive position is reported" do
      attrs = PilotConformance.snapshot()
      attrs = put_in(attrs, ["payload", "comparisons", Access.at(1), "position"], 5)

      assert {:error, %PilotError{issues: issues}} = EvidenceSnapshotInput.parse(attrs)
      assert Enum.any?(issues, &(&1["code"] == "non_consecutive_position"))
    end

    test "strict schemas reject unknown fields, wrong types, and bad versions" do
      for mutation <- [
            &Map.put(&1, "unknown", true),
            &Map.put(&1, "schema_version", 2),
            &Map.delete(&1, "payload"),
            &Map.put(&1, "study_revision_id", "not-a-uuid")
          ] do
        assert {:error, %PilotError{}} =
                 PilotConformance.snapshot() |> mutation.() |> EvidenceSnapshotInput.parse()
      end
    end
  end

  describe "PILOT-03: request rejection" do
    test "duplicate candidate values are rejected" do
      attrs = PilotConformance.request()
      attrs = put_in(attrs, ["candidate_grid", "plan_count_candidates"], [5, 5])

      assert {:error, %PilotError{code: "validation_failed", issues: issues}} =
               PilotRequest.parse(attrs)

      assert Enum.any?(issues, &(&1["code"] == "invalid_candidate_grid"))
    end

    test "candidate positions keep the declared plan-major order" do
      request = PilotConformance.parsed_request()
      payload = PilotConformance.parsed_payload!()

      {:ok, items} =
        Work.canonical_items(request, payload)

      assert Enum.take(items, 4) |> Enum.map(& &1["candidate_position"]) == [0, 0, 1, 1]

      assert Enum.take(items, 4) |> Enum.map(& &1["comparison_position"]) == [0, 1, 0, 1]

      assert Enum.map(items, & &1["plan_count"]) == [5, 5, 5, 5, 6, 6, 6, 6]
      assert Enum.map(items, & &1["attacks_per_plan"]) == [10, 10, 12, 12, 10, 10, 12, 12]
    end

    test "unknown fields, wrong types, and unsupported versions are rejected" do
      for mutation <- [
            &Map.put(&1, "unknown", true),
            &Map.put(&1, "schema_version", 2),
            &Map.put(&1, "pilot_id", 12),
            &Map.delete(&1, "selection")
          ] do
        assert {:error, %PilotError{}} =
                 PilotConformance.request() |> mutation.() |> PilotRequest.parse()
      end
    end
  end

  describe "PILOT-04: comparison stream is declaration driven" do
    test "grouped and interleaved declarations give each identity the same seed" do
      grouped = build_items([{"core", 4}, {"core", 6}, {"edge", 4}, {"edge", 6}])
      interleaved = build_items([{"core", 4}, {"edge", 4}, {"core", 6}, {"edge", 6}])

      assert seeds_by_identity(grouped) == seeds_by_identity(interleaved)

      assert seeds_by_identity(grouped) == %{
               {"core", 4} => 700_001,
               {"core", 6} => 700_003,
               {"edge", 4} => 1_700_001,
               {"edge", 6} => 1_700_003
             }
    end

    test "the base seed moves every stream and no comparison position shares a seed" do
      pairs = [{"core", 4}, {"edge", 6}]
      base = seeds_by_identity(build_items(pairs))
      shifted = seeds_by_identity(build_items(pairs, 800_001))

      assert map_size(base) == 2
      assert Map.values(base) |> Enum.uniq() |> length() == 2
      assert shifted == Map.new(base, fn {identity, seed} -> {identity, seed + 100_000} end)
    end
  end

  describe "PILOT-05: configured limits" do
    test "a missing configuration fails safely without blocking other work" do
      Application.delete_env(:network_defense, Limits)

      assert {:error, %PilotError{issues: [issue]}} = PilotConformance.snapshot_input()
      assert issue["code"] == "configuration_invalid"

      assert {:error, %PilotError{issues: [issue]}} =
               PilotRequest.parse(PilotConformance.request())

      assert issue["code"] == "configuration_invalid"
    end

    test "a malformed configuration fails safely" do
      Application.put_env(:network_defense, Limits, snapshot_payload_bytes: "many")

      assert {:error, %PilotError{issues: [issue]}} = PilotConformance.snapshot_input()
      assert issue["code"] == "configuration_invalid"
    end

    test "the snapshot payload limit rejects an oversize document without truncation" do
      put_limits(snapshot_payload_bytes: 10)

      assert {:error, %PilotError{code: "request_too_large"}} =
               PilotConformance.snapshot_input()
    end

    test "the snapshot comparison limit rejects an oversize document" do
      put_limits(snapshot_comparisons: 1)

      assert {:error, %PilotError{code: "validation_failed", issues: issues}} =
               PilotConformance.snapshot_input()

      assert Enum.any?(issues, &(&1["code"] == "invalid_analysis_setting"))
    end

    test "every declared request limit rejects an oversize request" do
      original = Application.get_env(:network_defense, Limits)
      on_exit(fn -> Application.put_env(:network_defense, Limits, original) end)

      for {limit, overrides, path} <- [
            {:comparison_count, [comparison_count: 1], ["expected_comparisons"]},
            {:candidate_count, [candidate_count: 1], ["candidate_grid", "plan_count_candidates"]},
            {:plans_per_side, [plans_per_side: 4],
             ["candidate_grid", "plan_count_candidates", 0]},
            {:attack_columns, [attack_columns: 4],
             ["candidate_grid", "attacks_per_plan_candidates", 0]},
            {:work_items, [work_items: 4], ["candidate_grid"]},
            {:outer_subsamples, [outer_subsamples: 10], ["pilot_sampling", "outer_subsamples"]},
            {:bootstrap_replicates, [bootstrap_replicates: 100],
             ["precision", "bootstrap_replicates"]}
          ] do
        Application.put_env(
          :network_defense,
          Limits,
          Keyword.merge(original, overrides)
        )

        assert {:error, %PilotError{code: "validation_failed", issues: issues}} =
                 PilotRequest.parse(PilotConformance.request()),
               "expected limit #{inspect(limit)} to reject"

        assert Enum.any?(issues, &(&1["path"] == path)),
               "expected limit #{inspect(limit)} at path #{inspect(path)}"
      end
    end

    test "the candidate request limit rejects an oversize comparison request" do
      put_limits(candidate_request_bytes: 100)

      request = PilotConformance.parsed_request()
      payload = PilotConformance.parsed_payload!()

      {:ok, [item | _rest]} =
        Work.canonical_items(request, payload)

      assert {:error, %PilotError{code: "request_too_large"}} =
               Work.candidate_request(request, payload, item)
    end
  end

  describe "PILOT-07: fixed selection and tie order" do
    test "the shared key keeps runtime, plans, attacks, and position in that order" do
      summaries = [
        summary(0, 5, 10, 100.0),
        summary(1, 6, 12, 90.0),
        summary(2, 6, 10, 100.0),
        summary(3, 6, 12, 100.0)
      ]

      assert Enum.map(
               Enum.sort_by(summaries, &PilotResult.selection_key/1),
               & &1.candidate_position
             ) ==
               [1, 2, 3, 0]

      assert %Recommendation{candidate_position: 1, plan_count: 6, attacks_per_plan: 12} =
               Assembler.recommendation(summaries)
    end

    test "the fixed order prefers more plans, then fewer attacks, then the lower position" do
      summaries = [
        summary(0, 6, 12, 100.0),
        summary(1, 5, 10, 100.0),
        summary(2, 6, 10, 100.0),
        summary(3, 6, 10, 100.0)
      ]

      assert Enum.map(
               Enum.sort_by(summaries, &PilotResult.selection_key/1),
               & &1.candidate_position
             ) ==
               [2, 3, 0, 1]
    end

    test "the predicted runtime keeps the fixed historical formula" do
      # Fixture runtime evidence: plan median 4.0 ms, attack median 2.0 ms,
      # two tiers, and two strategy groups.
      payload = PilotConformance.parsed_payload!()

      assert PilotResult.predicted_runtime(payload, 5, 10) == 480.0
      assert PilotResult.predicted_runtime(payload, 5, 12) == 560.0
      assert PilotResult.predicted_runtime(payload, 6, 10) == 576.0
      assert PilotResult.predicted_runtime(payload, 6, 12) == 672.0
    end

    test "no passing candidate yields no recommendation" do
      summaries = [summary(0, 5, 10, 100.0), summary(1, 6, 10, 90.0)]

      assert Assembler.recommendation(Enum.map(summaries, &%{&1 | all_comparisons_passed: false})) ==
               nil
    end
  end

  describe "PILOT-06: stored candidate row order" do
    test "reversed rows are rejected even though every row is present" do
      stored = PilotConformance.stored_result()
      reversed = Map.put(stored, "candidate_results", Enum.reverse(stored["candidate_results"]))

      assert {:error, %PilotError{code: "validation_failed", issues: issues}} =
               PilotResult.parse(
                 reversed,
                 PilotConformance.parsed_request(),
                 PilotConformance.parsed_payload!()
               )

      assert Enum.any?(issues, fn issue ->
               issue["code"] == "changed_candidate_result" and
                 issue["path"] == ["candidate_results"]
             end)
    end

    test "a swapped pair is rejected, while missing rows keep their own diagnostics" do
      [first, second | rest] = PilotConformance.stored_result()["candidate_results"]

      assert {:error, %PilotError{issues: swapped}} =
               PilotResult.parse(
                 Map.put(PilotConformance.stored_result(), "candidate_results", [
                   second,
                   first | rest
                 ]),
                 PilotConformance.parsed_request(),
                 PilotConformance.parsed_payload!()
               )

      assert Enum.any?(swapped, &(&1["code"] == "changed_candidate_result"))

      assert {:error, %PilotError{issues: missing}} =
               PilotResult.parse(
                 Map.put(PilotConformance.stored_result(), "candidate_results", [first | rest]),
                 PilotConformance.parsed_request(),
                 PilotConformance.parsed_payload!()
               )

      assert Enum.any?(missing, &(&1["code"] == "incomplete_pilot"))
    end
  end

  describe "PILOT-05: malformed limit configuration" do
    test "every malformed key list returns one bounded typed error" do
      for config <- [:bad, [1], [{"bad", 1}], [snapshot_payload_bytes: 1] ++ [:bad]] do
        Application.put_env(:network_defense, Limits, config)

        assert {:error, %PilotError{code: "workflow_failed", issues: [issue]}} = Limits.fetch()
        assert issue["code"] == "configuration_invalid"
        assert String.length(issue["message"]) <= 256
      end
    end

    test "a missing configuration returns one bounded typed error" do
      Application.delete_env(:network_defense, Limits)

      assert {:error, %PilotError{code: "workflow_failed", issues: [issue]}} = Limits.fetch()
      assert issue["code"] == "configuration_invalid"
    end

    test "a non-list configuration returns one bounded typed error" do
      for config <- [%{}, "bad", nil] do
        Application.put_env(:network_defense, Limits, config)

        assert {:error, %PilotError{code: "workflow_failed", issues: [issue]}} = Limits.fetch()
        assert issue["code"] == "configuration_invalid"
      end
    end
  end

  defp summary(position, plan_count, attacks_per_plan, runtime) do
    %CandidateSummary{
      candidate_position: position,
      plan_count: plan_count,
      attacks_per_plan: attacks_per_plan,
      worst_guarded_half_width: 0.1,
      all_comparisons_informative: true,
      non_informative_comparison_positions: [],
      all_comparisons_passed: true,
      predicted_runtime_ms: runtime
    }
  end

  defp put_limits(overrides) do
    original = Application.get_env(:network_defense, Limits)
    Application.put_env(:network_defense, Limits, Keyword.merge(original, overrides))
    on_exit(fn -> Application.put_env(:network_defense, Limits, original) end)
  end

  defp restore_limits(nil), do: Application.delete_env(:network_defense, Limits)
  defp restore_limits(value), do: Application.put_env(:network_defense, Limits, value)

  # Build a snapshot payload and a request from the two checked-in comparisons.
  # The evidence matrices stay unchanged. Only identities, positions, and the
  # declared order change, so the test isolates the stream rule.
  defp build_items(pairs, base_seed \\ 700_001) do
    source = PilotConformance.snapshot()
    core = Enum.at(source["payload"]["comparisons"], 0)
    edge = Enum.at(source["payload"]["comparisons"], 1)

    comparisons =
      pairs
      |> Enum.with_index()
      |> Enum.map(fn {{tier, budget}, position} ->
        template = if tier == "core", do: core, else: edge

        %{
          "position" => position,
          "identity" => Map.merge(template["identity"], %{"tier" => tier, "budget" => budget}),
          "evidence" => template["evidence"],
          "provenance" => template["provenance"]
        }
      end)

    attrs = put_in(source, ["payload", "comparisons"], comparisons)
    payload = assert_ok(SnapshotPayload.parse(attrs["payload"]))

    request_attrs =
      PilotConformance.request()
      |> Map.put("expected_comparisons", Enum.map(comparisons, & &1["identity"]))
      |> put_in(["candidate_grid", "plan_count_candidates"], [5])
      |> put_in(["candidate_grid", "attacks_per_plan_candidates"], [10])
      |> put_in(["pilot_sampling", "seed"], base_seed)

    request = assert_ok(PilotRequest.parse(request_attrs))
    {:ok, items} = Work.canonical_items(request, payload)
    items
  end

  defp seeds_by_identity(items) do
    items
    |> Enum.map(fn item ->
      {{item["identity"]["tier"], item["identity"]["budget"]}, item["stream_seed"]}
    end)
    |> Map.new()
  end

  defp assert_ok({:ok, value}), do: value
  defp assert_ok({:error, error}), do: raise("expected ok, got: #{inspect(error)}")
end
