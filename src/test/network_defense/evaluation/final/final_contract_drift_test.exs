defmodule NetworkDefense.Evaluation.Final.ContractDriftTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonRequest, ComparisonStatistics}
  alias NetworkDefense.Evaluation.Family.Contracts.{HolmResponse, Identity}
  alias NetworkDefense.Evaluation.Final.Contracts.{Assertions, Request, Result, SnapshotInput}
  alias NetworkDefense.Evaluation.FinalConformance

  # Definitions that must agree because they share one meaning.
  #
  # These are targeted equality checks, not a schema framework. A difference
  # that is intentional is stated in the test that keeps it, so an accidental
  # change on one side fails here instead of passing unnoticed.

  @final_schema_dir "priv/evaluation/final/v1/schemas"
  @family_schema_dir "priv/evaluation/family/v1/schemas"
  @comparison_schema_dir "priv/evaluation/contracts/v1/schemas"

  test "DRIFT-01: the Final contracts share one identifier, UUID, and identity definition" do
    definitions = Enum.map(["snapshot", "request", "result"], &definitions(&1, @final_schema_dir))
    [base | others] = definitions

    for definition <- ["uuid", "identifier", "identity"], other <- others do
      assert other[definition] == base[definition], definition
    end
  end

  test "DRIFT-02: the Final request and result use the same assertion definition" do
    request = definitions("request", @final_schema_dir)
    result = definitions("result", @final_schema_dir)

    assert result["assertions"] == request["assertions"]

    assert struct_fields(Assertions) == Enum.sort(request["assertions"]["required"]),
           "the encoded assertion claim must hold exactly the documented fields"
  end

  test "DRIFT-03: the Final identity agrees with the shared Family identity" do
    final = definitions("snapshot", @final_schema_dir)["identity"]
    family = definitions("request", @family_schema_dir)["identity"]

    # Final narrows the reference and the outcome to the accepted values. Every
    # other field and every constraint stays shared.
    assert final["required"] == family["required"]
    assert final["properties"]["tier"] == family["properties"]["tier"]
    assert final["properties"]["budget"] == family["properties"]["budget"]
    assert final["properties"]["alternative"] == family["properties"]["alternative"]
    assert final["properties"]["reference"]["enum"] == ["cvss"]
    assert final["properties"]["outcome"]["enum"] == ["mission_impact"]

    assert Enum.sort(Enum.map(Identity.__schema__(:fields), &Atom.to_string/1)) ==
             Enum.sort(final["required"])
  end

  test "DRIFT-04: the Final evidence agrees with the accepted comparison evidence" do
    final = definitions("snapshot", @final_schema_dir)
    comparison = definitions("request", @comparison_schema_dir)

    for definition <- ["evidence", "alternative_side", "reference_side"] do
      assert final[definition] == comparison[definition], definition
    end

    # Final keeps the accepted attack-column minimum and raises only the plan
    # row minimum, because one Final row must carry the accepted attack count.
    final_plan = final["plan"]
    comparison_plan = comparison["plan"]

    assert final_plan["properties"]["mission_impacts"]["minItems"] == 10
    assert comparison_plan["properties"]["mission_impacts"]["minItems"] == 1

    without_minimum = fn plan ->
      update_in(plan, ["properties", "mission_impacts"], &Map.delete(&1, "minItems"))
    end

    assert without_minimum.(final_plan) == without_minimum.(comparison_plan)
  end

  test "DRIFT-05: each contract struct holds exactly its documented wire fields" do
    assert struct_fields(SnapshotInput) == required("snapshot")
    assert struct_fields(Request) == required("request")
    assert struct_fields(Result) == required("result")
  end

  test "DRIFT-06: the checked-in member requests are the wire values the adapter must send" do
    request = FinalConformance.request()

    assert Enum.map(FinalConformance.member_requests!(), & &1["resampling"]["seed"]) ==
             request["comparison_seeds"]

    for {member_request, position} <- Enum.with_index(FinalConformance.member_requests!()) do
      assert {:ok, parsed} = ComparisonRequest.parse(member_request)

      assert ComparisonRequest.to_params(parsed) == member_request,
             "member #{position} must survive the strict parser unchanged"
    end
  end

  test "DRIFT-07: every checked-in member response parses against its member request" do
    requests = FinalConformance.member_requests!()
    responses = FinalConformance.member_responses()

    assert length(requests) == length(responses)

    for {member_request, response} <- Enum.zip(requests, responses) do
      {:ok, parsed_request} = ComparisonRequest.parse(member_request)
      assert {:ok, %ComparisonStatistics{}} = ComparisonStatistics.parse(response, parsed_request)
    end
  end

  test "DRIFT-08: the checked-in correction request repeats the declared family" do
    request = FinalConformance.request()
    correction = FinalConformance.correction_request()

    assert correction["expected_comparisons"] == request["expected_comparisons"]
    assert correction["family_id"] == request["family_id"]
    assert correction["method"] == request["method"]
    assert correction["alpha"] == request["analysis"]["alpha"]

    assert Enum.map(correction["raw_results"], & &1["identity"]) ==
             request["expected_comparisons"]

    assert Enum.map(correction["raw_results"], & &1["raw_p_value"]) ==
             FinalConformance.raw_p_values()

    assert {:ok, %HolmResponse{}} =
             HolmResponse.parse(
               FinalConformance.correction_response(),
               correction_fixture_request()
             )
  end

  defp correction_fixture_request do
    alias NetworkDefense.Evaluation.Family.Contracts.HolmRequest

    {:ok, request} = HolmRequest.parse(FinalConformance.correction_request())
    request
  end

  defp definitions(contract, dir) do
    :network_defense
    |> Application.app_dir(dir)
    |> Path.join("#{contract}.schema.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("definitions")
  end

  defp struct_fields(module),
    do: module.__schema__(:fields) |> Enum.map(&Atom.to_string/1) |> Enum.sort()

  defp required(contract) do
    :network_defense
    |> Application.app_dir(@final_schema_dir)
    |> Path.join("#{contract}.schema.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("required")
    |> Enum.sort()
  end
end
