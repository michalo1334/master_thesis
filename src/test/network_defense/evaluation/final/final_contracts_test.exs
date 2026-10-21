defmodule NetworkDefense.Evaluation.Final.ContractsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonRequest, ComparisonStatistics}
  alias NetworkDefense.Evaluation.EvidenceSnapshot
  alias NetworkDefense.Evaluation.Family.Contracts.Identity

  alias NetworkDefense.Evaluation.Final.Contracts.{
    FinalError,
    Request,
    Result,
    SnapshotInput,
    SnapshotPayload
  }

  alias NetworkDefense.Evaluation.Final.{Member, Wire}
  alias NetworkDefense.Evaluation.FinalConformance
  alias NetworkDefense.Evaluation.Pilot.Contracts.PilotResult

  # Acceptance coverage in this file:
  #   S5-01  strict Final snapshot input and its rejections
  #   S5-03  a non-recommended Pilot cannot supply Final counts
  #   S5-04  repeated counts must equal the Pilot recommendation
  #   S5-08  crossed matrices keep independent rows and shared columns
  #   S5-09  stored-result relations
  #   S5-10  caller-asserted assertion metadata

  setup do
    raw_snapshot = FinalConformance.snapshot()
    snapshot_input = FinalConformance.snapshot_input!()
    payload = snapshot_input.payload

    request =
      FinalConformance.parsed_request!(
        "0f9e8d7c-6b5a-4c3d-9e2f-1a2b3c4d5e6f",
        42
      )

    stored_snapshot = %EvidenceSnapshot{
      id: request.snapshot_id,
      study_revision_id: snapshot_input.study_revision_id,
      phase: :final,
      schema_version: 1,
      family_id: snapshot_input.family_id,
      payload: SnapshotPayload.to_params(payload)
    }

    members = members(request, payload)

    %{
      snapshot: raw_snapshot,
      parsed_snapshot: snapshot_input,
      payload: payload,
      request: request,
      stored_snapshot: stored_snapshot,
      members: members
    }
  end

  defp members(request, payload) do
    Enum.map(Enum.with_index(payload.comparisons), fn {comparison, position} ->
      {:ok, comparison_request} = Member.comparison_request(request, payload, position)
      {:ok, statistics} = ComparisonStatistics.parse(response(position), comparison_request)

      %{identity: comparison.identity, request: comparison_request, statistics: statistics}
    end)
  end

  defp response(index), do: Enum.at(FinalConformance.member_responses(), index)

  defp stored_result(request, members) do
    adjustments = FinalConformance.correction_response()["results"]

    comparisons =
      members
      |> Enum.zip(adjustments)
      |> Enum.map(fn {member, adjustment} ->
        %{
          "identity" => Identity.to_params(member.identity),
          "statistics" => ComparisonStatistics.to_params(member.statistics),
          "adjustment" => %{
            "adjusted_p_value" => adjustment["adjusted_p_value"],
            "reject_null" => adjustment["reject_null"]
          }
        }
      end)

    %{
      "schema_version" => 1,
      "evidence_role" => request.evidence_role,
      "assertion_basis" => "caller_asserted",
      "family_id" => request.family_id,
      "method" => request.method,
      "alpha" => request.analysis.alpha,
      "family_size" => length(comparisons),
      "study_revision_id" => request.study_revision_id,
      "snapshot_id" => request.snapshot_id,
      "source_pilot_run_id" => request.source_pilot_run_id,
      "plan_count" => request.plan_count,
      "attacks_per_plan" => request.attacks_per_plan,
      "assertions" => NetworkDefense.Contracts.to_params(request.assertions),
      "comparisons" => comparisons
    }
  end

  test "S5-01: the checked-in Final snapshot input passes every check", %{
    parsed_snapshot: snapshot
  } do
    assert snapshot.phase == "final"
    assert snapshot.payload.evidence_role == "final"
    assert [_, _] = snapshot.payload.comparisons
  end

  test "S5-01: the Final create path rejects the Pilot phase and the Pilot role", %{
    snapshot: snapshot
  } do
    assert {:error, %FinalError{code: "validation_failed"}} =
             SnapshotInput.parse(%{snapshot | "phase" => "pilot"})

    pilot_role =
      update_in(snapshot, ["payload", "evidence_role"], fn _role -> "pilot" end)

    assert {:error, %FinalError{code: "validation_failed"}} = SnapshotInput.parse(pilot_role)
  end

  test "S5-01: the Final create path rejects unknown fields and missing provenance", %{
    snapshot: snapshot
  } do
    assert {:error, %FinalError{code: "validation_failed"}} =
             SnapshotInput.parse(Map.put(snapshot, "unexpected", true))

    [comparison | rest] = get_in(snapshot, ["payload", "comparisons"])

    without_provenance =
      put_in(snapshot, ["payload", "comparisons"], [Map.delete(comparison, "provenance") | rest])

    assert {:error, %FinalError{code: "validation_failed"}} =
             SnapshotInput.parse(without_provenance)
  end

  test "S5-01: the Final create path rejects broken declared order and duplicates", %{
    snapshot: snapshot
  } do
    assert {:error, %FinalError{code: "validation_failed"}} =
             SnapshotInput.parse(update_in(snapshot, ["payload", "comparisons"], &reorder(&1)))

    assert {:error, %FinalError{code: "validation_failed"}} =
             SnapshotInput.parse(update_in(snapshot, ["payload", "comparisons"], &duplicate(&1)))

    assert {:error, %FinalError{code: "validation_failed"}} =
             SnapshotInput.parse(update_in(snapshot, ["payload", "comparisons"], &shift(&1)))
  end

  test "S5-01: the Final create path rejects a broken attack column count", %{snapshot: snapshot} do
    wider = update_in(snapshot, ["payload", "comparisons"], &extra_attack_column/1)

    assert {:error, %FinalError{code: "validation_failed"} = error} = SnapshotInput.parse(wider)

    assert Enum.any?(error.issues, &(&1["code"] == "attack_column_count_mismatch"))
  end

  test "S5-01: the Final create path rejects a duplicate plan ID", %{snapshot: snapshot} do
    duplicated =
      update_in(snapshot, ["payload", "comparisons"], fn comparisons ->
        [comparison | rest] = comparisons
        plans = comparison["evidence"]["alternative"]["plans"]
        [first | _] = plans
        plans = [first | List.replace_at(plans, 1, first)]

        [
          put_in(comparison, ["evidence", "alternative", "plans"], plans)
          | rest
        ]
      end)

    assert {:error, %FinalError{} = error} = SnapshotInput.parse(duplicated)
    assert Enum.any?(error.issues, &(&1["code"] == "duplicate_plan_id"))
  end

  test "S5-08: the adapter keeps independent rows and a shared ordered column list", %{
    request: request,
    payload: payload
  } do
    assert [first, second] = Member.declared_items(request)

    assert first["identity"]["tier"] == "core"
    assert second["identity"]["tier"] == "edge"
    assert first["position"] == 0
    refute Map.has_key?(first, "request")

    requests =
      payload.comparisons
      |> Enum.with_index()
      |> Enum.map(fn {_comparison, position} ->
        {:ok, comparison_request} = Member.comparison_request(request, payload, position)
        %{"request" => ComparisonRequest.to_params(comparison_request)}
      end)

    Enum.zip(requests, payload.comparisons)
    |> Enum.each(fn {item, comparison} ->
      evidence = item["request"]["evidence"]
      assert evidence["attack_seeds"] == comparison.evidence.attack_seeds

      assert evidence["alternative"]["strategy"] == comparison.evidence.alternative.strategy
      assert length(evidence["alternative"]["plans"]) == request.plan_count
      assert length(evidence["reference"]["plans"]) == request.plan_count

      for side <- ["alternative", "reference"] do
        for plan <- evidence[side]["plans"] do
          assert length(plan["mission_impacts"]) == request.attacks_per_plan
        end
      end
    end)

    seeds =
      Enum.map(requests, fn item -> item["request"]["resampling"]["seed"] end)

    assert seeds == request.comparison_seeds
    assert length(Enum.uniq(seeds)) == length(seeds)
  end

  test "S5-04: a Final request with a different plan or attack count is rejected", %{
    request: request,
    stored_snapshot: snapshot,
    payload: payload
  } do
    eight_plans = %{request | plan_count: 7}

    assert {:error, %FinalError{} = error} =
             Request.matches_snapshot(eight_plans, snapshot, payload)

    assert Enum.any?(error.issues, &(&1["code"] == "plan_count_mismatch"))

    fewer_attacks = %{request | attacks_per_plan: 9}

    assert {:error, %FinalError{} = error} =
             Request.matches_snapshot(fewer_attacks, snapshot, payload)

    assert Enum.any?(error.issues, &(&1["code"] == "attack_count_mismatch"))
  end

  test "S5-04: one explicit seed is required for every declared comparison", %{request: request} do
    dropped = Map.update!(request, :comparison_seeds, &List.delete_at(&1, 0))
    attrs = Request.to_params(dropped)

    assert {:error, %FinalError{} = error} = Request.parse(attrs)
    assert Enum.any?(error.issues, &(&1["code"] == "seed_count_mismatch"))
  end

  describe "seed scalars" do
    test "N2-01: an invalid seed value keeps the request schema diagnostic", %{request: request} do
      base = Request.to_params(request)

      invalid = [-1, true, 1.5, "5101"]

      for seed <- invalid do
        attrs = Map.put(base, "comparison_seeds", [seed | Enum.drop(base["comparison_seeds"], 1)])

        assert {:error, %FinalError{} = error} = Request.parse(attrs),
               "expected a bounded error for seed #{inspect(seed)}"

        assert error.code == "validation_failed"
        assert error.issues == []
        assert error.schema_errors != []
      end
    end

    test "N2-02: the declared seed count is still checked", %{request: request} do
      base = Request.to_params(request)
      declared = length(base["expected_comparisons"])

      for seeds <- [Enum.take(base["comparison_seeds"], 1), base["comparison_seeds"] ++ [1]] do
        attrs = Map.put(base, "comparison_seeds", seeds)

        assert {:error, %FinalError{code: "validation_failed", issues: [issue]}} =
                 Request.parse(attrs),
               "expected a seed count error for #{inspect(seeds)}"

        assert issue["code"] == "seed_count_mismatch"

        assert issue["details"] == %{
                 "declared" => declared,
                 "supplied" => length(seeds)
               }
      end
    end

    test "N2-02b: an empty seed list keeps the request schema diagnostic", %{request: request} do
      attrs = Map.put(Request.to_params(request), "comparison_seeds", [])

      assert {:error, %FinalError{} = error} = Request.parse(attrs)
      assert error.code == "validation_failed"
      assert error.issues == []
      assert error.schema_errors != []
    end

    test "N2-03: the declared seeds survive the parser unchanged", %{request: request} do
      assert {:ok, parsed} = Request.parse(FinalConformance.request())

      assert parsed.comparison_seeds == request.comparison_seeds
      assert parsed.comparison_seeds == FinalConformance.request()["comparison_seeds"]
    end
  end

  describe "snapshot input diagnostics" do
    test "F5-01: a value that is not a map keeps the bounded schema diagnostic" do
      for value <- [[], nil, "snapshot", 42] do
        assert {:error, %FinalError{} = error} = SnapshotInput.parse(value),
               "expected a bounded error for #{inspect(value)}"

        assert error.code == "validation_failed"
        assert error.schema_errors != []
        assert error.issues == []
      end
    end

    test "F5-02: a malformed map and a wrong role keep the bounded schema diagnostic" do
      malformed = Map.delete(FinalConformance.snapshot(), "family_id")

      assert {:error, %FinalError{code: "validation_failed", schema_errors: [_ | _]}} =
               SnapshotInput.parse(malformed)

      wrong_role = put_in(FinalConformance.snapshot(), ["phase"], "pilot")

      assert {:error, %FinalError{code: "validation_failed", schema_errors: [_ | _]}} =
               SnapshotInput.parse(wrong_role)
    end

    test "F5-03: the checked-in snapshot parses without persistence fields" do
      assert {:ok, input} = SnapshotInput.parse(FinalConformance.snapshot())
      assert input.phase == "final"

      assert input
             |> Map.from_struct()
             |> Map.keys()
             |> Enum.sort() ==
               Enum.sort([:study_revision_id, :phase, :schema_version, :family_id, :payload])
    end
  end

  describe "oversized member requests" do
    test "F3-01: a generated request above the member byte cap is a Final error" do
      request = oversized_request!()
      payload = oversized_payload!()

      assert {:error, %FinalError{} = error} = Member.comparison_request(request, payload, 0)
      assert error.code == "request_too_large"
      assert Enum.any?(error.issues, &(&1["code"] == "request_too_large"))

      assert {:error, %FinalError{code: "request_too_large"}} = Member.preflight(request, payload)
    end
  end

  test "F7-01: a valid stored result keeps its comparisons unchanged", %{
    request: request,
    payload: payload
  } do
    members = members(request, payload)
    stored = stored_result(request, members)

    assert {:ok, parsed} = Result.parse(stored, request, members)
    assert Result.to_params(parsed) == stored
    assert length(parsed.comparisons) == length(request.expected_comparisons)
  end

  test "S5-03: a secondary Pilot outcome cannot supply Final counts", %{request: request} do
    for outcome <- ["insufficient", "not_recommended"] do
      pilot = %PilotResult{
        outcome: outcome,
        recommendation: nil,
        family_id: request.family_id,
        study_revision_id: request.study_revision_id,
        expected_comparisons: request.expected_comparisons
      }

      assert {:error, %FinalError{} = error} = Request.matches_pilot(request, pilot)
      assert Enum.any?(error.issues, &(&1["code"] == "pilot_not_recommended"))
    end
  end

  test "S5-04: a recommended Pilot with different counts cannot override the request", %{
    request: request
  } do
    pilot = recommended_pilot(request, plan_count: request.plan_count + 1)

    assert {:error, %FinalError{} = error} = Request.matches_pilot(request, pilot)
    assert Enum.any?(error.issues, &(&1["code"] == "count_mismatch"))
  end

  test "S5-04: a recommended Pilot with a different source family is rejected", %{
    request: request
  } do
    pilot = recommended_pilot(request, family_id: "another-family")

    assert {:error, %FinalError{} = error} = Request.matches_pilot(request, pilot)
    assert Enum.any?(error.issues, &(&1["code"] == "changed_pilot_source"))
  end

  test "S5-03: a matching recommended Pilot binds the request", %{request: request} do
    assert :ok = Request.matches_pilot(request, recommended_pilot(request))
  end

  test "S5-09: the stored Final result passes every relation", %{
    request: request,
    members: members,
    stored_snapshot: snapshot,
    payload: payload
  } do
    :ok = Request.matches_snapshot(request, snapshot, payload)

    result = stored_result(request, members)

    assert {:ok, %Result{} = parsed} = Result.parse(result, request, members)
    assert parsed.comparisons |> Enum.map(& &1.identity.tier) == ["core", "edge"]
    assert parsed.assertion_basis == "caller_asserted"
    assert parsed.family_size == 2
  end

  test "S5-09: a changed source, method, alpha, or assertion basis is rejected", %{
    request: request,
    members: members
  } do
    result = stored_result(request, members)

    for {key, value} <- [
          {"snapshot_id", "11111111-2222-3333-4444-555555555555"},
          {"source_pilot_run_id", 7},
          {"family_id", "other-family"},
          {"method", "bonferroni"},
          {"alpha", 0.01},
          {"family_size", 3},
          {"assertion_basis", "verified"}
        ] do
      assert {:error, %FinalError{}} =
               Result.parse(Map.put(result, key, value), request, members),
             "expected #{key} to be rejected"
    end
  end

  test "S5-09: changed comparison order, statistics, or adjustment is rejected", %{
    request: request,
    members: members
  } do
    result = stored_result(request, members)

    assert {:error, %FinalError{}} =
             Result.parse(
               put_in(result, ["comparisons"], Enum.reverse(result["comparisons"])),
               request,
               members
             )

    assert {:error, %FinalError{}} =
             Result.parse(
               put_in(result, ["comparisons", Access.at(0), "statistics"], %{}),
               request,
               members
             )

    assert {:error, %FinalError{}} =
             Result.parse(
               put_in(
                 result,
                 ["comparisons", Access.at(0), "adjustment", "adjusted_p_value"],
                 0.0
               ),
               request,
               members
             )

    assert {:error, %FinalError{}} =
             Result.parse(
               put_in(
                 result,
                 ["comparisons", Access.at(0), "adjustment", "adjusted_p_value"],
                 0.9
               ),
               request,
               members
             )

    assert {:error, %FinalError{}} = Result.parse(result, request, Enum.reverse(members))
  end

  test "S5-10: the caller assertions are required and labelled", %{request: request} do
    assert request.assertions.final_evidence_collected_after_pilot
    assert request.assertions.pilot_observations_excluded

    attrs =
      request
      |> Request.to_params()
      |> put_in(["assertions", "pilot_observations_excluded"], false)

    assert {:error, %FinalError{code: "validation_failed"}} = Request.parse(attrs)

    attrs =
      request
      |> Request.to_params()
      |> put_in(["assertions", "collection_completed_at"], "yesterday")

    assert {:error, %FinalError{code: "validation_failed"}} = Request.parse(attrs)
  end

  test "S5-09: the bounded error envelope decodes as a Final failure" do
    error = FinalError.changed_member()
    wire = Wire.error(error)

    assert {:ok, %FinalError{} = decoded} = FinalError.parse_envelope(wire)
    assert decoded.code == error.code
    assert decoded.issues == error.issues
  end

  test "S5-09: the Final request carries no evidence matrix" do
    attrs = FinalConformance.request()

    refute Map.has_key?(attrs, "evidence")
    refute Map.has_key?(attrs, "payload")
    refute Map.has_key?(attrs, "comparisons")
  end

  defp recommended_pilot(request, overrides \\ []) do
    counts = %{
      plan_count: Keyword.get(overrides, :plan_count, request.plan_count),
      attacks_per_plan: Keyword.get(overrides, :attacks_per_plan, request.attacks_per_plan)
    }

    %PilotResult{
      outcome: "recommended",
      family_id: Keyword.get(overrides, :family_id, request.family_id),
      study_revision_id: request.study_revision_id,
      expected_comparisons: request.expected_comparisons,
      recommendation: struct(NetworkDefense.Evaluation.Pilot.Contracts.Recommendation, counts)
    }
  end

  defp reorder(comparisons), do: Enum.reverse(comparisons)
  defp duplicate([first | _rest]), do: [first, first]

  defp shift([first, second | rest]) do
    [put_in(first, ["position"], 1), put_in(second, ["position"], 2) | rest]
  end

  # One extra attack column with unchanged plan rows changes the shared column
  # count without changing any matrix row.
  defp extra_attack_column([first | rest]) do
    seeds = first["evidence"]["attack_seeds"]
    [put_in(first, ["evidence", "attack_seeds"], seeds ++ [Enum.max(seeds) + 1]) | rest]
  end

  # F3 boundary data: the accepted caps allow more evidence than one member
  # request may carry. These dimensions keep the snapshot inside the shared
  # snapshot cap and push the generated member request over its byte cap.
  @oversized_plans 128
  @oversized_attacks 512

  defp oversized_request! do
    %Request{
      schema_version: 1,
      evidence_role: "final",
      method: "holm",
      family_id: "family-example",
      study_revision_id: "4f4a33c6-cc8e-4ac1-b145-18647a928e49",
      snapshot_id: "0f9e8d7c-6b5a-4c3d-9e2f-1a2b3c4d5e6f",
      source_pilot_run_id: 1,
      plan_count: @oversized_plans,
      attacks_per_plan: @oversized_attacks,
      expected_comparisons: [oversized_identity()],
      comparison_seeds: [5101],
      analysis: %NetworkDefense.Evaluation.Final.Contracts.Analysis{
        alpha: 0.05,
        confidence_level: 0.95,
        test_alternative: "two_sided",
        bootstrap_replicates: 1
      },
      assertions: %NetworkDefense.Evaluation.Final.Contracts.Assertions{
        final_evidence_collected_after_pilot: true,
        pilot_observations_excluded: true,
        collection_completed_at: "2026-02-14T09:30:00Z"
      }
    }
  end

  defp oversized_identity do
    %Identity{
      tier: "core",
      budget: 4,
      alternative: "simulation_informed",
      reference: "cvss",
      outcome: "mission_impact"
    }
  end

  defp oversized_payload! do
    evidence = %NetworkDefense.Evaluation.Comparison.Contracts.Evidence{
      outcome: "mission_impact",
      attack_seeds: Enum.to_list(9_001..(9_000 + @oversized_attacks)),
      alternative: oversized_side("simulation_informed", "alt"),
      reference: oversized_side("cvss", "ref")
    }

    %SnapshotPayload{
      schema_version: 1,
      evidence_role: "final",
      comparisons: [
        %NetworkDefense.Evaluation.Final.Contracts.ComparisonEvidence{
          position: 0,
          identity: oversized_identity(),
          evidence: evidence,
          provenance: %NetworkDefense.Evaluation.Pilot.Contracts.Provenance{
            graph_revision_ids: ["graph-revision-final"],
            model_revision: "model-final-v1",
            collection_seed: 5_000,
            source_run_ids: ["final-collection-run"],
            environment: "conformance"
          }
        }
      ]
    }
  end

  defp oversized_side(strategy, prefix) do
    plans =
      for index <- 1..@oversized_plans do
        %NetworkDefense.Evaluation.Comparison.Contracts.PlanEvidence{
          id: "#{prefix}-plan-#{index}",
          mission_impacts: List.duplicate(1.234567, @oversized_attacks)
        }
      end

    %NetworkDefense.Evaluation.Comparison.Contracts.ComparisonSide{
      strategy: strategy,
      plans: plans
    }
  end
end
