defmodule Mix.Tasks.Evaluate.StudyTest do
  use NetworkDefense.DataCase, async: false

  import ExUnit.CaptureIO

  alias Mix.Error
  alias Mix.Task
  alias Mix.Tasks.Evaluate.Study
  alias NetworkDefense.Evaluation
  alias NetworkDefense.Evaluation.AnalysisClient
  alias NetworkDefense.EvaluationFixtures

  @run_id "11111111-1111-4111-8111-111111111111"
  @run_second "22222222-2222-4222-8222-222222222222"

  setup do
    previous = Application.get_env(:network_defense, :analysis_service)
    Application.put_env(:network_defense, :analysis_service, max_zip_bytes: 10_000_000)
    on_exit(fn -> Application.put_env(:network_defense, :analysis_service, previous) end)

    :meck.new(Evaluation, [:passthrough])
    on_exit(fn -> :meck.unload() end)
    :ok
  end

  test "writes the validated result and reports its digest" do
    output = Path.join(System.tmp_dir!(), "study-#{System.unique_integer([:positive])}.zip")
    spec = write_spec(%{"study_id" => "study-1"})

    :meck.expect(Evaluation, :analyze_study, fn tier_runs, mode, loaded ->
      assert tier_runs == [{"small", @run_id}, {"medium", @run_second}]
      assert mode == :pilot
      assert loaded["study_id"] == "study-1"
      {:ok, "study-zip"}
    end)

    Task.reenable("evaluate.study")

    response =
      capture_io(fn ->
        Study.run([
          "--spec",
          spec,
          "--tier",
          "small=#{@run_id}",
          "--tier",
          "medium=#{@run_second}",
          "--mode",
          "pilot",
          "--output",
          output
        ])
      end)
      |> Jason.decode!()

    assert File.read!(output) == "study-zip"
    assert response["study_id"] == "study-1"
    assert response["mode"] == "pilot"
    assert response["path"] == output
    assert response["byte_size"] == 9
    assert response["sha256"] == Base.encode16(:crypto.hash(:sha256, "study-zip"), case: :lower)

    File.rm!(output)
    File.rm!(spec)
  end

  test "requires spec, mode, output, and at least one tier" do
    Task.reenable("evaluate.study")

    assert_raise Error, "missing required option --spec", fn ->
      Study.run([])
    end

    spec = write_spec(%{"study_id" => "study-1"})
    Task.reenable("evaluate.study")

    assert_raise Error, "missing required option --tier", fn ->
      Study.run(["--spec", spec, "--mode", "pilot", "--output", "out.zip"])
    end

    File.rm!(spec)
  end

  test "rejects an unknown mode before packaging" do
    spec = write_spec(%{"study_id" => "study-1"})
    Task.reenable("evaluate.study")

    assert_raise Error, "mode must be pilot or analyze", fn ->
      Study.run([
        "--spec",
        spec,
        "--tier",
        "small=#{@run_id}",
        "--mode",
        "unknown",
        "--output",
        "out.zip"
      ])
    end

    File.rm!(spec)
  end

  test "rejects malformed, unsafe, and duplicate tier values" do
    spec = write_spec(%{"study_id" => "study-1"})

    assert_tier_error(
      spec,
      ["small=not-a-uuid"],
      "invalid tier run id in --tier small=not-a-uuid"
    )

    assert_tier_error(spec, ["=#{@run_id}"], "tier label must not be empty")
    assert_tier_error(spec, ["a/b=#{@run_id}"], "tier label is unsafe")
    assert_tier_error(spec, ["novalue"], "invalid --tier value: novalue")

    assert_tier_error(
      spec,
      ["small=#{@run_id}", "small=#{@run_second}"],
      "duplicate tier label"
    )

    assert_tier_error(
      spec,
      ["small=#{@run_id}", "medium=#{@run_id}"],
      "duplicate tier run id"
    )

    File.rm!(spec)
  end

  test "rejects an unreadable or invalid spec" do
    Task.reenable("evaluate.study")

    assert_raise Error, "cannot read study spec: enoent", fn ->
      Study.run([
        "--spec",
        "/nonexistent/study.json",
        "--tier",
        "small=#{@run_id}",
        "--mode",
        "pilot",
        "--output",
        "out.zip"
      ])
    end

    broken = write_spec_raw("{not json")
    Task.reenable("evaluate.study")

    assert_raise Error, ~r/invalid study spec JSON/, fn ->
      Study.run([
        "--spec",
        broken,
        "--tier",
        "small=#{@run_id}",
        "--mode",
        "pilot",
        "--output",
        "out.zip"
      ])
    end

    File.rm!(broken)
  end

  test "rejects a malformed finite value before submission" do
    spec =
      legacy_spec()
      |> put_in(["pilot", "ci_half_width"], "1e400")
      |> write_spec()

    Task.reenable("evaluate.study")

    assert_raise Error, "study specification is invalid", fn ->
      Study.run([
        "--spec",
        spec,
        "--tier",
        "small=#{@run_id}",
        "--mode",
        "pilot",
        "--output",
        "out.zip"
      ])
    end

    File.rm!(spec)
  end

  test "derives tier labels from --tier when the specification omits tiers" do
    completed = completed_run()
    output = temp_output("study-legacy")
    spec = write_spec(legacy_spec())

    :meck.new(AnalysisClient, [:passthrough])

    :meck.expect(AnalysisClient, :analyze_study, fn bundle, study_id, :pilot ->
      assert study_id == legacy_spec()["study_id"]
      assert Enum.map(study_tiers(bundle), & &1["label"]) == ["small"]
      {:ok, "study-zip"}
    end)

    Task.reenable("evaluate.study")

    response =
      capture_io(fn ->
        Study.run([
          "--spec",
          spec,
          "--tier",
          "small=#{completed.id}",
          "--mode",
          "pilot",
          "--output",
          output
        ])
      end)
      |> Jason.decode!()

    assert File.read!(output) == "study-zip"
    assert response["study_id"] == legacy_spec()["study_id"]
    assert response["mode"] == "pilot"
    assert response["byte_size"] == 9

    File.rm!(output)
    File.rm!(spec)
  end

  test "rejects a declared tier list that conflicts with --tier values" do
    completed = completed_run()
    spec = legacy_spec() |> Map.put("tiers", ["small", "medium"]) |> write_spec()

    Task.reenable("evaluate.study")

    assert_raise Error, "study tier labels do not match --tier values", fn ->
      Study.run([
        "--spec",
        spec,
        "--tier",
        "small=#{completed.id}",
        "--mode",
        "pilot",
        "--output",
        "out.zip"
      ])
    end

    File.rm!(spec)
  end

  defp completed_run do
    manifest_id = "study-task-#{System.unique_integer([:positive])}"

    assert {:ok, _manifest} =
             EvaluationFixtures.save_manifest(manifest_id, EvaluationFixtures.analysis_manifest())

    assert {:ok, run} = Evaluation.start(manifest_id)
    assert {:ok, completed} = Evaluation.run(run.id)
    completed
  end

  defp legacy_spec, do: Map.delete(EvaluationFixtures.study_specification(), "tiers")

  defp study_tiers(bundle) do
    {:ok, entries} = :zip.extract(bundle, [:memory])

    entries
    |> Map.new(fn {name, content} -> {to_string(name), content} end)
    |> Map.fetch!("study.json")
    |> Jason.decode!()
    |> Map.fetch!("tiers")
  end

  defp temp_output(name) do
    Path.join(System.tmp_dir!(), "#{name}-#{System.unique_integer([:positive])}.zip")
  end

  defp assert_tier_error(spec, tier_args, message) do
    Task.reenable("evaluate.study")

    assert_raise Error, message, fn ->
      Study.run(
        ["--spec", spec, "--mode", "pilot", "--output", "out.zip"] ++
          Enum.flat_map(tier_args, &["--tier", &1])
      )
    end
  end

  defp write_spec(content) do
    write_spec_raw(Jason.encode!(content))
  end

  defp write_spec_raw(content) do
    path = Path.join(System.tmp_dir!(), "study-spec-#{System.unique_integer([:positive])}.json")
    File.write!(path, content)
    path
  end
end
