defmodule NetworkDefense.Evaluation.ComparisonContractsTest do
  use ExUnit.Case, async: true

  alias NetworkDefense.Evaluation.Comparison.Contracts.{
    ComparisonError,
    ComparisonRequest,
    ComparisonStatistics
  }

  alias Gust.DAG.{ErrorParser, NonRecError}
  alias Gust.DAG.Parser.File, as: DAGFile
  alias NetworkDefense.Evaluation.Comparison.{SchemaValidator, TaskFailure, Wire}
  alias NetworkDefense.Evaluations

  @contracts_root Path.expand("../../../../contracts/evaluation/comparison/v1", __DIR__)

  test "CONTRACT-01: valid shared requests materialize" do
    for name <- ["crossed-small.request.json", "integer-number.request.json"] do
      assert {:ok, %ComparisonRequest{}} = name |> valid_fixture() |> ComparisonRequest.parse()
    end
  end

  test "CONTRACT-02: every shared invalid request has the expected issues" do
    @contracts_root
    |> Path.join("invalid/*.request.json")
    |> Path.wildcard()
    |> Enum.each(fn request_path ->
      expected_path = String.replace(request_path, ".request.json", ".expected.json")
      expected = read_json(expected_path)
      assert expected["http_status"] == 422, Path.basename(expected_path)

      assert {:error, %ComparisonError{} = error} =
               request_path |> read_json() |> ComparisonRequest.parse()

      if error.issues == [] do
        assert error.code == "validation_failed"
        assert error.schema_errors != []
      else
        actual = Enum.map(error.issues, &Map.take(&1, ["code", "path", "details"]))
        assert actual == expected["issues"], Path.basename(request_path)
      end
    end)
  end

  test "CONTRACT-03: canonical statistics and error examples validate" do
    statistics = valid_fixture("informative.statistics.json")

    assert {:ok, request} =
             "crossed-small.request.json" |> valid_fixture() |> ComparisonRequest.parse()

    assert {:ok, %ComparisonStatistics{}} = ComparisonStatistics.parse(statistics, request)

    for name <- ["validation.error.json", "schema-validation.error.json"] do
      assert {:ok, %ComparisonError{}} =
               name |> valid_fixture() |> ComparisonError.parse_envelope()
    end
  end

  test "REL-04: direct malformed statistics changesets return errors without raising" do
    assert {:ok, request} =
             "crossed-small.request.json" |> valid_fixture() |> ComparisonRequest.parse()

    changeset =
      ComparisonStatistics.changeset(%ComparisonStatistics{}, %{"interval" => %{}}, request)

    refute changeset.valid?
  end

  test "CONTRACT-04: Draft 4 distinguishes integers, floats, and booleans" do
    valid = valid_fixture("crossed-small.request.json")

    for invalid <- [
          put_in(valid, ["resampling", "seed"], 1.0),
          put_in(valid, ["resampling", "seed"], true)
        ] do
      assert {:error, %ComparisonError{issues: [], schema_errors: diagnostics}} =
               ComparisonRequest.parse(invalid)

      assert diagnostics != []
    end
  end

  test "CONTRACT-05: schema validation collects nested issues and caps them" do
    invalid =
      valid_fixture("crossed-small.request.json")
      |> put_in(["resampling", "seed"], true)
      |> put_in(["interval", "confidence_level"], "0.95")

    assert {:error, %ComparisonError{schema_errors: diagnostics}} =
             ComparisonRequest.parse(invalid)

    assert Enum.count_until(diagnostics, 2) == 2

    many_unknowns =
      Enum.reduce(1..60, valid_fixture("crossed-small.request.json"), fn index, request ->
        Map.put(request, "unknown_#{index}", index)
      end)

    assert {:error, %ComparisonError{schema_errors: capped}} =
             ComparisonRequest.parse(many_unknowns)

    assert diagnostic_count(capped) == 50
  end

  test "CONTRACT-06: schema diagnostics keep native paths without typed normalization" do
    invalid =
      valid_fixture("crossed-small.request.json")
      |> Map.put("123", true)
      |> Map.put("a/b~c", true)

    assert {:error, %ComparisonError{issues: [], schema_errors: diagnostics}} =
             ComparisonRequest.parse(invalid)

    assert Enum.all?(diagnostics, &is_binary(&1["path"]))
  end

  test "CONTRACT-07: atom keys and non-JSON values fail before workflow submission" do
    assert {:error, %ComparisonError{issues: [atom_issue]}} =
             Evaluations.submit_comparison(%{schema_version: 1})

    assert atom_issue["code"] == "invalid_type"

    invalid = valid_fixture("crossed-small.request.json") |> Map.put("bad", self())

    assert {:error, %ComparisonError{issues: [json_issue]}} =
             Evaluations.submit_comparison(invalid)

    assert json_issue["code"] == "invalid_type"
  end

  test "CONTRACT-08: every shared invalid response example is rejected" do
    statistics_paths =
      @contracts_root |> Path.join("invalid/*.statistics.json") |> Path.wildcard()

    error_paths = @contracts_root |> Path.join("invalid/*.error.json") |> Path.wildcard()

    assert MapSet.new([
             "duplicate-warning.statistics.json",
             "missing-assessment.statistics.json",
             "schema-version-float.statistics.json"
           ])
           |> MapSet.subset?(MapSet.new(Enum.map(statistics_paths, &Path.basename/1)))

    Enum.each(statistics_paths, fn path ->
      payload = read_json(path)

      assert match?({:error, %ComparisonError{}}, SchemaValidator.validate(:statistics, payload)),
             Path.basename(path)
    end)

    assert MapSet.new([
             "detail-key-limit.error.json",
             "detail-list-limit.error.json",
             "message-max-length.error.json",
             "missing-version.error.json",
             "schema-version-float.error.json",
             "utf8-message-bytes.error.json"
           ])
           |> MapSet.subset?(MapSet.new(Enum.map(error_paths, &Path.basename/1)))

    Enum.each(error_paths, fn path ->
      payload = read_json(path)

      rejected =
        case SchemaValidator.validate(:error, payload) do
          {:error, %ComparisonError{}} ->
            true

          :ok ->
            match?(
              {:error, :materialization_failed},
              ComparisonError.materialize_envelope(payload)
            )
        end

      assert rejected, Path.basename(path)
    end)
  end

  test "CONTRACT-09: schema version requires an integer JSON token" do
    assert {:error, %ComparisonError{schema_errors: [_ | _]}} =
             @contracts_root
             |> Path.join("invalid/schema-version-float.request.json")
             |> read_json()
             |> ComparisonRequest.parse()

    for {kind, suffix} <- [statistics: "statistics", error: "error"] do
      payload =
        @contracts_root
        |> Path.join("invalid/schema-version-float.#{suffix}.json")
        |> read_json()

      assert {:error, %ComparisonError{schema_errors: [_ | _]}} =
               SchemaValidator.validate(kind, payload)
    end
  end

  test "CONTRACT-10: the logical contract path links to the packaged schema source" do
    authoritative = Path.join(@contracts_root, "schemas")
    packaged = Application.app_dir(:network_defense, "priv/evaluation/contracts/v1/schemas")

    assert {:ok, %File.Stat{type: :symlink}} = File.lstat(authoritative)

    assert File.read_link!(authoritative) ==
             "../../../../src/priv/evaluation/contracts/v1/schemas"

    for name <- ["request.schema.json", "statistics.schema.json", "error.schema.json"] do
      assert File.read!(Path.join(packaged, name)) == File.read!(Path.join(authoritative, name))
    end
  end

  test "CONTRACT-11: an error message can contain at most 256 UTF-8 bytes" do
    valid = valid_fixture("validation.error.json")

    accepted =
      put_in(valid, ["error", "issues", Access.at(0), "message"], String.duplicate("é", 128))

    rejected =
      put_in(valid, ["error", "issues", Access.at(0), "message"], String.duplicate("é", 129))

    assert :ok = SchemaValidator.validate(:error, accepted)
    assert {:ok, %ComparisonError{}} = ComparisonError.parse_envelope(accepted)
    assert :ok = SchemaValidator.validate(:error, rejected)
    assert {:error, :materialization_failed} = ComparisonError.materialize_envelope(rejected)
  end

  test "WORKFLOW-01: Gust loads the approved EXS DAG source" do
    definitions = DAGFile.parse_folder(Application.fetch_env!(:gust, :dags_folder))

    assert {"evaluation_comparison", {:ok, definition}} =
             Enum.find(definitions, fn {name, _result} -> name == "evaluation_comparison" end)

    assert definition.task_list == ["prepare", "compare"]
    assert definition.tasks["compare"].store_result
  end

  test "WORKFLOW-02: typed task failures round-trip without stacktrace data" do
    error =
      ComparisonError.new(
        "validation_failed",
        "attack_column_count_mismatch",
        ["evidence", "alternative"],
        "Invalid alignment.",
        %{"expected" => 10, "actual" => 9}
      )

    exception =
      assert_raise NonRecError, fn ->
        TaskFailure.raise_permanent(error)
      end

    persisted = ErrorParser.parse(exception) |> Jason.encode!() |> Jason.decode!()
    assert {:ok, decoded} = TaskFailure.decode(persisted)
    assert decoded.code == "validation_failed"
    assert hd(decoded.issues)["details"] == %{"expected" => 10, "actual" => 9}
    refute Map.has_key?(Wire.error(decoded), "stacktrace")
  end

  test "SCHEMA-08 and SCHEMA-11: diagnostics are canonical and omit submitted values" do
    private_value = "private-value-that-must-not-leak"

    invalid =
      valid_fixture("crossed-small.request.json")
      |> Map.put("unknown", private_value)

    assert {:error, %ComparisonError{issues: [], schema_errors: diagnostics} = error} =
             ComparisonRequest.parse(invalid)

    assert diagnostics != []
    assert :ok = SchemaValidator.validate(:error, Wire.error(error))
    refute error |> Wire.error() |> Jason.encode!() |> String.contains?(private_value)
  end

  test "SCHEMA-09: nested validator causes are retained and round-trip through Gust storage" do
    invalid =
      read_json(Path.join(@contracts_root, "invalid/unsupported-alternative.request.json"))

    assert {:error, %ComparisonError{schema_errors: validator_diagnostics}} =
             ComparisonRequest.parse(invalid)

    assert diagnostic_count(validator_diagnostics) > length(validator_diagnostics)

    error =
      ComparisonError.schema_failure([
        %{
          "message" => "All branches failed.",
          "path" => "#/evidence",
          "causes" => [
            %{"message" => "Invalid type.", "path" => "#/evidence/value", "causes" => []}
          ]
        }
      ])

    exception = assert_raise NonRecError, fn -> TaskFailure.raise_permanent(error) end
    persisted = ErrorParser.parse(exception) |> Jason.encode!() |> Jason.decode!()

    assert {:ok, %ComparisonError{issues: [], schema_errors: [diagnostic]}} =
             TaskFailure.decode(persisted)

    assert [%{"message" => "Invalid type."}] =
             Enum.map(diagnostic["causes"], &Map.take(&1, ["message"]))
  end

  test "SCHEMA-14: deeply nested persisted diagnostics stop at the total budget" do
    nested =
      Enum.reduce(1..100, %{"message" => "leaf", "path" => "#", "causes" => []}, fn
        _index, cause -> %{"message" => "nested", "path" => "#", "causes" => [cause]}
      end)

    envelope = %{
      "schema_version" => 1,
      "error" => %{"code" => "validation_failed", "schema_errors" => [nested]}
    }

    assert {:error, :materialization_failed} = ComparisonError.parse_envelope(envelope)
  end

  test "WIRE-04: canonical serialization excludes struct metadata" do
    assert {:ok, request} =
             "crossed-small.request.json" |> valid_fixture() |> ComparisonRequest.parse()

    serialized = Wire.request(request)
    refute inspect(serialized) =~ "__struct__"
    assert :ok = SchemaValidator.validate(:request, serialized)
  end

  defp valid_fixture(name), do: read_json(Path.join([@contracts_root, "valid", name]))
  defp read_json(path), do: path |> File.read!() |> Jason.decode!()

  defp diagnostic_count(diagnostics) do
    Enum.reduce(diagnostics, 0, fn diagnostic, count ->
      count + 1 + diagnostic_count(diagnostic["causes"])
    end)
  end
end
