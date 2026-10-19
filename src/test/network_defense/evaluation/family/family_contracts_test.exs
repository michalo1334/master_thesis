defmodule NetworkDefense.Evaluation.Family.FamilyContractsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonRequest, ComparisonStatistics}

  alias NetworkDefense.Evaluation.FamilyConformance

  alias NetworkDefense.Evaluation.Family.Contracts.{
    FamilyError,
    FamilyRequest,
    FamilyResult,
    HolmRequest,
    HolmResponse,
    Identity
  }

  @root Path.expand("../../../../../contracts/evaluation/family/v1", __DIR__)

  defp read_json(relative_path) do
    @root |> Path.join(relative_path) |> File.read!() |> Jason.decode!()
  end

  defp valid_request, do: read_json("valid/holm-small.request.json")

  defp invalid_request(name), do: read_json("invalid/#{name}.request.json")

  defp parse!(attrs) do
    assert {:ok, %FamilyRequest{} = request} = FamilyRequest.parse(attrs)
    request
  end

  defp holm_request!(raw_values, alpha \\ 0.05) do
    identities = valid_request()["expected_comparisons"]

    attrs = %{
      "schema_version" => 1,
      "family_id" => "primary-comparisons-small",
      "method" => "holm",
      "alpha" => alpha,
      "expected_comparisons" => identities,
      "raw_results" =>
        identities
        |> Enum.zip(raw_values)
        |> Enum.map(fn {identity, raw} ->
          %{"identity" => identity, "raw_p_value" => raw}
        end)
    }

    assert {:ok, %HolmRequest{} = request} = HolmRequest.parse(attrs)
    request
  end

  defp response_attrs(%HolmRequest{} = request, adjusted_values) do
    %{
      "schema_version" => 1,
      "family_id" => request.family_id,
      "method" => "holm",
      "alpha" => request.alpha,
      "family_size" => length(request.expected_comparisons),
      "results" =>
        request.raw_results
        |> Enum.zip(adjusted_values)
        |> Enum.map(fn {raw, adjusted} ->
          %{
            "identity" => Identity.to_params(raw.identity),
            "raw_p_value" => raw.raw_p_value,
            "adjusted_p_value" => adjusted,
            "reject_null" => adjusted <= request.alpha
          }
        end)
    }
  end

  describe "FAM-01: valid family declaration" do
    test "parses and keeps the declared order" do
      request = parse!(valid_request())

      assert request.family_id == "primary-comparisons-small"
      assert request.evidence_role == "synthetic_prototype"
      assert request.method == "holm"
      assert request.alpha == 0.05

      assert Enum.map(request.expected_comparisons, &Identity.key/1) == [
               {"core", 4, "simulation_informed", "cvss", "mission_impact"},
               {"core", 6, "simulation_informed", "cvss", "mission_impact"},
               {"edge", 4, "heuristic", "cvss", "mission_impact"},
               {"edge", 6, "heuristic", "cvss", "mission_impact"}
             ]

      assert Enum.map(request.comparisons, & &1.identity.budget) == [4, 6, 4, 6]
    end

    test "the supplied comparison list is order independent" do
      attrs = valid_request()
      reordered = %{attrs | "comparisons" => Enum.reverse(attrs["comparisons"])}

      assert Enum.map(parse!(reordered).expected_comparisons, &Identity.key/1) ==
               Enum.map(parse!(attrs).expected_comparisons, &Identity.key/1)
    end
  end

  describe "FAM-02: declared family consistency" do
    test "a repeated declared identity is reported" do
      assert {:error, %FamilyError{} = error} =
               FamilyRequest.parse(invalid_request("duplicate-expected-identity"))

      codes = Enum.map(error.issues, & &1["code"])
      assert "duplicate_expected_identity" in codes
      assert error.code == "validation_failed"
    end

    test "a repeated supplied identity is reported" do
      assert {:error, %FamilyError{} = error} =
               FamilyRequest.parse(invalid_request("duplicate-comparison-identity"))

      codes = Enum.map(error.issues, & &1["code"])
      assert "duplicate_comparison_identity" in codes
    end

    test "a missing comparison is reported at its declared position" do
      assert {:error, %FamilyError{issues: [issue]}} =
               FamilyRequest.parse(invalid_request("missing-comparison"))

      assert issue["code"] == "missing_comparison"
      assert issue["path"] == ["expected_comparisons", 2]
    end

    test "an unexpected comparison is reported" do
      assert {:error, %FamilyError{issues: [issue]}} =
               FamilyRequest.parse(invalid_request("unexpected-comparison"))

      assert issue["code"] == "unexpected_comparison"
      assert issue["path"] == ["comparisons", 4, "identity"]
    end

    test "a mismatched identity is reported per field" do
      assert {:error, %FamilyError{issues: [issue]}} =
               FamilyRequest.parse(invalid_request("identity-mismatch"))

      assert issue["code"] == "identity_mismatch"
      assert issue["path"] == ["comparisons", 0, "identity", "alternative"]
      assert issue["details"] == %{"declared" => "simulation_informed", "request" => "heuristic"}
    end
  end

  describe "FAM-05: nested comparison requests" do
    test "every member request passes the comparison contract" do
      assert {:ok, %FamilyRequest{} = request} = FamilyRequest.parse(valid_request())

      assert Enum.all?(request.comparisons, fn input ->
               match?(
                 {:ok, _},
                 ComparisonRequest.parse(ComparisonRequest.to_params(input.request))
               )
             end)
    end

    test "a ragged member matrix is reported at the member path" do
      assert {:error, %FamilyError{code: "validation_failed", issues: [issue]}} =
               FamilyRequest.parse(invalid_request("nested-attack-column-mismatch"))

      assert issue["code"] == "attack_column_count_mismatch"

      assert issue["path"] == [
               "comparisons",
               1,
               "request",
               "evidence",
               "alternative",
               "plans",
               0,
               "mission_impacts"
             ]

      # The member index and the path identify the member. The diagnostic must
      # never copy the supplied identity text.
      assert issue["details"]["member_index"] == 1
      refute Map.has_key?(issue["details"], "member")
    end

    test "a duplicated plan within one member is reported with its member context" do
      assert {:error, %FamilyError{code: "validation_failed", issues: [issue]}} =
               FamilyRequest.parse(invalid_request("nested-duplicate-plan-id"))

      assert issue["code"] == "duplicate_plan_id"

      assert issue["path"] == [
               "comparisons",
               0,
               "request",
               "evidence",
               "alternative",
               "plans",
               5,
               "id"
             ]

      assert issue["details"]["member_index"] == 0
    end

    test "the nested error never reports a struct that dropped a supplied field" do
      # The nested check reads the supplied JSON, not the cast struct.
      attrs = invalid_request("nested-attack-column-mismatch")
      request = put_in(attrs, ["comparisons", Access.at(1), "request", "schema_version"], 1)

      assert {:error, %FamilyError{issues: issues}} = FamilyRequest.parse(request)
      assert Enum.any?(issues, &(&1["code"] == "attack_column_count_mismatch"))
    end
  end

  describe "FAM-03: strict rejection" do
    test "an unsupported correction method is rejected" do
      assert {:error, %FamilyError{code: "validation_failed", schema_errors: [_ | _]}} =
               FamilyRequest.parse(invalid_request("unsupported-method"))
    end

    test "an unknown field is rejected" do
      attrs = Map.put(valid_request(), "family_size", 3)

      assert {:error, %FamilyError{schema_errors: [_ | _]}} = FamilyRequest.parse(attrs)
    end

    test "a missing required field is rejected" do
      attrs = Map.delete(valid_request(), "evidence_role")

      assert {:error, %FamilyError{schema_errors: [_ | _]}} = FamilyRequest.parse(attrs)
    end

    test "a numeric string is not coerced" do
      attrs = Map.put(valid_request(), "alpha", "0.05")

      assert {:error, %FamilyError{schema_errors: [_ | _]}} = FamilyRequest.parse(attrs)
    end

    test "alpha must stay strictly between zero and one" do
      for alpha <- [0, 1, 1.0, -0.05, 1.5] do
        assert {:error, %FamilyError{schema_errors: [_ | _]}} =
                 FamilyRequest.parse(Map.put(valid_request(), "alpha", alpha)),
               "expected alpha #{inspect(alpha)} to be rejected"
      end
    end

    test "a boolean budget is rejected" do
      attrs = valid_request()
      [first | rest] = attrs["expected_comparisons"]
      attrs = %{attrs | "expected_comparisons" => [%{first | "budget" => true} | rest]}

      assert {:error, %FamilyError{schema_errors: [_ | _]}} = FamilyRequest.parse(attrs)
    end

    test "an over-long identifier is rejected" do
      attrs = Map.put(valid_request(), "family_id", String.duplicate("a", 129))

      assert {:error, %FamilyError{schema_errors: [_ | _]}} = FamilyRequest.parse(attrs)
    end

    test "a value that is not a JSON object is rejected" do
      assert {:error, %FamilyError{code: "validation_failed", issues: [issue]}} =
               FamilyRequest.parse([])

      assert issue["code"] == "invalid_type"
      assert issue["path"] == []
    end

    test "non-string keys are rejected" do
      assert {:error, %FamilyError{code: "validation_failed", issues: [issue]}} =
               FamilyRequest.parse(%{family_id: "small"})

      assert issue["code"] == "invalid_type"
      assert issue["path"] == []
    end

    test "a value that cannot be encoded is rejected" do
      attrs = Map.put(valid_request(), "family_id", {:not, "json"})

      assert {:error, %FamilyError{code: "validation_failed"}} = FamilyRequest.parse(attrs)
    end

    test "a request over the byte limit is rejected" do
      attrs = Map.put(valid_request(), "family_id", String.duplicate("a", 1_048_577))

      assert {:error, %FamilyError{code: "request_too_large"}} = FamilyRequest.parse(attrs)
    end
  end

  describe "FAM-04: typed identity" do
    test "field order in the encoded map does not change the key" do
      first =
        Identity.new(%{
          "tier" => "core",
          "budget" => 4,
          "alternative" => "simulation_informed",
          "reference" => "cvss",
          "outcome" => "mission_impact"
        })

      second =
        Identity.new(%{
          "outcome" => "mission_impact",
          "reference" => "cvss",
          "alternative" => "simulation_informed",
          "budget" => 4,
          "tier" => "core"
        })

      assert {:ok, left} = first
      assert {:ok, right} = second
      assert Identity.key(left) == Identity.key(right)
      assert Identity.matches?(left, right)
    end

    test "one different field changes the identity" do
      assert {:ok, left} = Identity.new(identity_params("core", 4))
      assert {:ok, right} = Identity.new(identity_params("core", 6))

      refute Identity.matches?(left, right)
    end

    test "strictly validates persisted identity shapes" do
      valid = identity_params("core", 4)
      valid_128 = %{valid | "tier" => "a" <> String.duplicate("b", 127)}

      invalid = [
        [],
        %{
          tier: "core",
          budget: 4,
          alternative: "simulation_informed",
          reference: "cvss",
          outcome: "mission_impact"
        },
        Map.put(valid, :tier, "core"),
        Map.delete(valid, "tier"),
        Map.put(valid, "seed", 700_001),
        Map.put(valid, "tier", 42),
        Map.put(valid, "budget", "4"),
        Map.put(valid, "budget", 0),
        Map.put(valid, "budget", -1),
        Map.put(valid, "tier", ""),
        Map.put(valid, "tier", "-core"),
        Map.put(valid, "tier", "core/name"),
        Map.put(valid, "tier", String.duplicate("a", 129))
      ]

      for attrs <- invalid, do: assert(:error = Identity.new(attrs))
      assert {:ok, identity} = Identity.new(valid_128)
      assert identity.tier == valid_128["tier"]
    end
  end

  describe "HOLM-02: decimal boundary agreement" do
    test "an exact boundary response keeps the reject decision" do
      # Four raw p-values of 0.075 give exactly 0.3 for a family of four.
      request = holm_request!([0.075, 0.075, 0.075, 0.075], 0.3)

      assert {:ok, %HolmResponse{results: results}} =
               HolmResponse.parse(response_attrs(request, [0.3, 0.3, 0.3, 0.3]), request)

      assert Enum.map(results, & &1.adjusted_p_value) == [0.3, 0.3, 0.3, 0.3]
      assert Enum.map(results, & &1.reject_null) == [true, true, true, true]
    end

    test "a decision that contradicts the boundary is rejected" do
      request = holm_request!([0.075, 0.075, 0.075, 0.075], 0.3)
      attrs = response_attrs(request, [0.3, 0.3, 0.3, 0.3])
      [first | rest] = attrs["results"]
      attrs = %{attrs | "results" => [%{first | "reject_null" => false} | rest]}

      assert {:error, %FamilyError{issues: [issue]}} = HolmResponse.parse(attrs, request)
      assert issue["path"] == ["results", 0, "reject_null"]
    end
  end

  describe "HOLM-01: correction response correlation" do
    test "a matching response is accepted" do
      request = holm_request!([0.01, 0.04, 0.03, 0.02])

      assert {:ok, %HolmResponse{family_size: 4, results: results}} =
               HolmResponse.parse(response_attrs(request, [0.04, 0.06, 0.06, 0.06]), request)

      assert Enum.map(results, & &1.adjusted_p_value) == [0.04, 0.06, 0.06, 0.06]
      assert Enum.map(results, & &1.reject_null) == [true, false, false, false]
    end

    test "a changed raw p-value is rejected" do
      request = holm_request!([0.01, 0.04, 0.03, 0.02])
      attrs = response_attrs(request, [0.04, 0.06, 0.06, 0.06])
      [first | rest] = attrs["results"]
      attrs = %{attrs | "results" => [%{first | "raw_p_value" => 0.5} | rest]}

      assert {:error, %FamilyError{issues: [issue]}} = HolmResponse.parse(attrs, request)
      assert issue["path"] == ["results", 0, "raw_p_value"]
    end

    test "a reordered row is rejected" do
      request = holm_request!([0.01, 0.04, 0.03, 0.02])
      attrs = response_attrs(request, [0.04, 0.06, 0.06, 0.06])
      attrs = %{attrs | "results" => Enum.reverse(attrs["results"])}

      assert {:error, %FamilyError{issues: issues}} = HolmResponse.parse(attrs, request)
      assert Enum.map(issues, & &1["path"]) |> Enum.member?(["results", 0, "identity"])
    end

    test "a missing row is rejected" do
      request = holm_request!([0.01, 0.04, 0.03, 0.02])
      attrs = response_attrs(request, [0.04, 0.06, 0.06, 0.06])
      attrs = %{attrs | "results" => Enum.take(attrs["results"], 2)}

      assert {:error, %FamilyError{issues: [issue]}} = HolmResponse.parse(attrs, request)
      assert issue["path"] == ["result_count"]
      assert issue["details"] == %{"expected" => 4, "actual" => 2}
    end

    test "an extra row is rejected" do
      request = holm_request!([0.01, 0.04, 0.03, 0.02])
      attrs = response_attrs(request, [0.04, 0.06, 0.06, 0.06])
      [_first | rest] = attrs["results"]
      attrs = %{attrs | "results" => attrs["results"] ++ List.delete_at(rest, 0)}

      assert {:error, %FamilyError{issues: [issue]}} = HolmResponse.parse(attrs, request)
      assert issue["path"] == ["result_count"]
    end

    test "an inconsistent decision is rejected" do
      request = holm_request!([0.01, 0.04, 0.03, 0.02])
      attrs = response_attrs(request, [0.04, 0.06, 0.06, 0.06])
      [first | rest] = attrs["results"]
      attrs = %{attrs | "results" => [%{first | "reject_null" => false} | rest]}

      assert {:error, %FamilyError{issues: [issue]}} = HolmResponse.parse(attrs, request)
      assert issue["path"] == ["results", 0, "reject_null"]
    end

    test "mismatched metadata is rejected" do
      request = holm_request!([0.01, 0.04, 0.03, 0.02])

      for {field, value} <- [{"family_id", "other"}, {"alpha", 0.01}, {"family_size", 7}] do
        attrs = response_attrs(request, [0.04, 0.06, 0.06, 0.06]) |> Map.put(field, value)

        assert {:error, %FamilyError{issues: [issue]}} = HolmResponse.parse(attrs, request)
        assert issue["path"] == [field]
      end
    end

    test "an unsupported method is rejected by the schema" do
      request = holm_request!([0.01, 0.04, 0.03, 0.02])
      attrs = response_attrs(request, [0.04, 0.06, 0.06, 0.06]) |> Map.put("method", "bonferroni")

      assert {:error, %FamilyError{code: "validation_failed", schema_errors: [_ | _]}} =
               HolmResponse.parse(attrs, request)
    end

    test "an adjusted p-value outside the unit interval is rejected" do
      request = holm_request!([0.01, 0.04, 0.03, 0.02])

      assert {:error, %FamilyError{code: "validation_failed", schema_errors: [_ | _]}} =
               HolmResponse.parse(response_attrs(request, [1.5, 0.06, 0.06, 0.06]), request)
    end
  end

  describe "RESULT-01: persisted family result" do
    setup do
      request = parse!(valid_request())

      members =
        request.expected_comparisons
        |> Enum.zip(request.comparisons)
        |> Enum.map(fn {identity, input} ->
          %{
            identity: identity,
            request: input.request,
            statistics: statistics_for(input.request, 0.01)
          }
        end)

      %{request: request, members: members}
    end

    test "is built from the request, the members, and the correction", %{
      request: request,
      members: members
    } do
      holm_request = holm_request!([0.01, 0.04, 0.03, 0.02])

      assert {:ok, response} =
               HolmResponse.parse(
                 response_attrs(holm_request, [0.04, 0.06, 0.06, 0.06]),
                 holm_request
               )

      assert {:ok, %FamilyResult{} = result} =
               FamilyResult.from_response(request, members, response)

      assert result.family_size == 4
      assert result.evidence_role == "synthetic_prototype"
      assert Enum.map(result.comparisons, & &1.identity.budget) == [4, 6, 4, 6]

      assert Enum.map(result.comparisons, & &1.adjustment.adjusted_p_value) == [
               0.04,
               0.06,
               0.06,
               0.06
             ]

      assert Enum.map(result.comparisons, & &1.statistics.test["raw_p_value"]) == [
               0.01,
               0.01,
               0.01,
               0.01
             ]
    end

    test "reads back through its own contract", %{request: request, members: members} do
      holm_request = holm_request!([0.01, 0.04, 0.03, 0.02])

      assert {:ok, response} =
               HolmResponse.parse(
                 response_attrs(holm_request, [0.04, 0.06, 0.06, 0.06]),
                 holm_request
               )

      assert {:ok, result} = FamilyResult.from_response(request, members, response)

      assert {:ok, %FamilyResult{} = read_back} =
               FamilyResult.parse(FamilyResult.to_params(result), request)

      assert read_back == result
    end

    test "rejects a reordered family", %{request: request, members: members} do
      holm_request = holm_request!([0.01, 0.04, 0.03, 0.02])

      assert {:ok, response} =
               HolmResponse.parse(
                 response_attrs(holm_request, [0.04, 0.06, 0.06, 0.06]),
                 holm_request
               )

      assert {:ok, result} = FamilyResult.from_response(request, members, response)

      attrs = FamilyResult.to_params(result)
      attrs = %{attrs | "comparisons" => Enum.reverse(attrs["comparisons"])}

      assert {:error, %FamilyError{code: "invalid_response_contract"}} =
               FamilyResult.parse(attrs, request)
    end

    test "rejects statistics that do not match their request", %{
      request: request,
      members: members
    } do
      holm_request = holm_request!([0.01, 0.04, 0.03, 0.02])

      assert {:ok, response} =
               HolmResponse.parse(
                 response_attrs(holm_request, [0.04, 0.06, 0.06, 0.06]),
                 holm_request
               )

      assert {:ok, result} = FamilyResult.from_response(request, members, response)

      attrs = FamilyResult.to_params(result)
      [first | rest] = attrs["comparisons"]
      statistics = put_in(first, ["statistics", "interval", "confidence_level"], 0.9)
      attrs = %{attrs | "comparisons" => [statistics | rest]}

      assert {:error, %FamilyError{issues: [issue]}} = FamilyResult.parse(attrs, request)
      assert issue["code"] == "family_result_invalid"
      assert issue["path"] == []
    end

    test "rejects an adjustment decision that contradicts its p-value", %{
      request: request,
      members: members
    } do
      holm_request = holm_request!([0.01, 0.04, 0.03, 0.02])

      assert {:ok, response} =
               HolmResponse.parse(
                 response_attrs(holm_request, [0.04, 0.06, 0.06, 0.06]),
                 holm_request
               )

      assert {:ok, result} = FamilyResult.from_response(request, members, response)

      attrs = FamilyResult.to_params(result)
      [first | rest] = attrs["comparisons"]
      comparison = put_in(first, ["adjustment", "reject_null"], false)
      attrs = %{attrs | "comparisons" => [comparison | rest]}

      assert {:error, %FamilyError{code: "invalid_response_contract"}} =
               FamilyResult.parse(attrs, request)
    end

    test "rejects a family size that does not match the declaration", %{
      request: request,
      members: members
    } do
      holm_request = holm_request!([0.01, 0.04, 0.03, 0.02])

      assert {:ok, response} =
               HolmResponse.parse(
                 response_attrs(holm_request, [0.04, 0.06, 0.06, 0.06]),
                 holm_request
               )

      assert {:ok, result} = FamilyResult.from_response(request, members, response)

      attrs = %{FamilyResult.to_params(result) | "family_size" => 5}

      assert {:error, %FamilyError{code: "invalid_response_contract"}} =
               FamilyResult.parse(attrs, request)
    end
  end

  describe "FAM-06: error envelope materialization" do
    test "materialization returns the typed error struct" do
      payload = read_json("valid/holm-small.error.json")

      assert {:ok, %FamilyError{} = error} = FamilyError.materialize_envelope(payload)
      assert is_struct(error, FamilyError)
      assert error.code == payload["error"]["code"]
      assert error.issues == payload["error"]["issues"]
      assert error.schema_version == 1
    end

    test "materialization keeps the bounded issue shape" do
      payload = read_json("valid/holm-small.error.json")

      assert {:ok, %FamilyError{code: "validation_failed", issues: [issue]}} =
               FamilyError.materialize_envelope(payload)

      assert issue["code"] == "changed_family_member"
      assert issue["path"] == ["comparisons", 1, "request", "resampling", "seed"]
      assert is_binary(issue["message"])
    end

    test "a typed error envelope round trips" do
      error = FamilyError.changed_member()
      payload = envelope(error)

      assert {:ok, %FamilyError{} = restored} = FamilyError.materialize_envelope(payload)
      assert restored.code == error.code
      assert restored.issues == error.issues
    end

    test "an unbounded issue value is rejected by materialization" do
      payload =
        %FamilyError{
          code: "validation_failed",
          issues: [
            %{
              "code" => "changed_family_member",
              "path" => [],
              "message" => String.duplicate("x", 300),
              "details" => %{}
            }
          ]
        }
        |> envelope()

      assert {:error, _reason} = FamilyError.materialize_envelope(payload)
    end
  end

  describe "CONFORMANCE-02: shared family paths" do
    test "each shared path links to the packaged canonical source" do
      for directory <- ["schemas", "valid", "invalid"] do
        shared = Path.join(FamilyConformance.root(), directory)

        packaged =
          Application.app_dir(:network_defense, "priv/evaluation/family/v1/#{directory}")

        assert {:ok, %File.Stat{type: :symlink}} = File.lstat(shared)

        assert File.read_link!(shared) ==
                 "../../../../src/priv/evaluation/family/v1/#{directory}"

        assert [_ | _] = names = packaged |> fixture_names()
        assert Enum.sort(names) == shared |> fixture_names() |> Enum.sort()

        for name <- names do
          assert File.read!(Path.join(packaged, name)) == File.read!(Path.join(shared, name))
        end
      end
    end
  end

  describe "CONFORMANCE-01: shared checked-in family examples" do
    # Both runtimes read these files. Python produces them and Elixir consumes
    # them, so a change in either runtime cannot pass unnoticed.

    test "the correction request repeats the declared family and its raw results" do
      request = parse!(valid_request())

      assert {:ok, %HolmRequest{} = holm_request} =
               HolmRequest.parse(FamilyConformance.correction_request())

      assert holm_request.family_id == request.family_id
      assert holm_request.alpha == request.alpha

      assert Enum.map(holm_request.expected_comparisons, &Identity.key/1) ==
               Enum.map(request.expected_comparisons, &Identity.key/1)

      assert Enum.map(holm_request.raw_results, & &1.raw_p_value) ==
               FamilyConformance.raw_p_values()
    end

    test "the correction response rebuilds the stored result exactly" do
      request = parse!(valid_request())

      assert {:ok, holm_request} = HolmRequest.parse(FamilyConformance.correction_request())

      assert {:ok, %HolmResponse{} = response} =
               HolmResponse.parse(FamilyConformance.correction_response(), holm_request)

      assert response.family_size == 4

      assert {:ok, %FamilyResult{} = result} =
               FamilyResult.from_response(request, FamilyConformance.members(), response)

      assert FamilyResult.to_params(result) == FamilyConformance.stored_result()
    end

    test "the stored result reads back through the public contract" do
      request = parse!(valid_request())

      assert {:ok, %FamilyResult{} = result} =
               FamilyResult.parse(FamilyConformance.stored_result(), request)

      assert result.evidence_role == "synthetic_prototype"
      assert result.family_size == 4
      assert Enum.map(result.comparisons, & &1.adjustment.reject_null) == decisions()
      assert Enum.map(result.comparisons, & &1.adjustment.adjusted_p_value) == adjusted()
    end

    test "one member rejects the raw null but not the corrected null" do
      # The example must keep a member that shows the correction at work.
      raw = FamilyConformance.raw_p_values()
      adjusted = FamilyConformance.adjusted_p_values()
      decisions = decisions()

      flips =
        Enum.with_index(raw)
        |> Enum.filter(fn {raw_value, index} ->
          raw_value <= 0.05 and Enum.at(adjusted, index) > 0.05 and
            Enum.at(decisions, index) == false
        end)

      assert [_one_flip] = flips
    end

    test "one member is not informative and stays in the family" do
      request = parse!(valid_request())

      assert {:ok, %FamilyResult{} = result} =
               FamilyResult.parse(FamilyConformance.stored_result(), request)

      third = Enum.at(result.comparisons, 2)
      assert third.statistics.assessment["status"] == "non_informative"
      assert third.adjustment.adjusted_p_value == 1.0
      assert third.adjustment.reject_null == false
    end
  end

  defp envelope(%FamilyError{} = error) do
    %{
      "schema_version" => 1,
      "error" => %{"code" => error.code, "issues" => error.issues}
    }
  end

  # Only top-level example files are compared. A nested directory (for
  # example the Holm correction examples) belongs to the same linked tree, and
  # hidden entries come from local review tools.
  defp fixture_names(directory) do
    directory
    |> File.ls!()
    |> Enum.reject(&String.starts_with?(&1, "."))
    |> Enum.filter(&File.regular?(Path.join(directory, &1)))
  end

  defp decisions, do: FamilyConformance.decisions()
  defp adjusted, do: FamilyConformance.adjusted_p_values()

  defp identity_params(tier, budget) do
    %{
      "tier" => tier,
      "budget" => budget,
      "alternative" => "simulation_informed",
      "reference" => "cvss",
      "outcome" => "mission_impact"
    }
  end

  defp statistics_for(request, raw_p_value) do
    attrs = %{
      "schema_version" => 1,
      "method" => "corrected_crossed_bootstrap_v1",
      "estimate" => %{"contrast" => "alternative_minus_reference", "value" => -1.42},
      "interval" => %{
        "confidence_level" => request.interval.confidence_level,
        "lower" => -2.31,
        "upper" => -0.58
      },
      "test" => %{
        "method" => "centered_crossed_bootstrap",
        "alternative" => request.test.alternative,
        "raw_p_value" => raw_p_value
      },
      "assessment" => %{"status" => "informative", "warnings" => []}
    }

    assert {:ok, %ComparisonStatistics{} = statistics} =
             ComparisonStatistics.parse(attrs, request)

    statistics
  end
end
