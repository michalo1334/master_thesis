defmodule NetworkDefense.RuntimeConfigTest do
  use ExUnit.Case, async: false

  alias NetworkDefense.RuntimeConfig

  test "reads a file-backed secret" do
    name = "NETWORK_DEFENSE_RUNTIME_CONFIG_TEST_SECRET"
    file_env = name <> "_FILE"

    path =
      Path.join(System.tmp_dir!(), "network-defense-secret-#{System.unique_integer([:positive])}")

    previous = System.get_env(file_env)

    File.write!(path, "secret\n")
    System.put_env(file_env, path)

    on_exit(fn ->
      File.rm(path)

      if previous, do: System.put_env(file_env, previous), else: System.delete_env(file_env)
    end)

    assert RuntimeConfig.read_secret(name) == "secret"
  end

  test "returns the configured role" do
    with_role("api", fn ->
      assert RuntimeConfig.role() == :api
      assert RuntimeConfig.api?()
      refute RuntimeConfig.worker?()
    end)

    with_role("worker", fn ->
      assert RuntimeConfig.role() == :worker
      refute RuntimeConfig.api?()
      assert RuntimeConfig.worker?()
    end)
  end

  test "defaults a missing role to worker" do
    assert with_role(nil, &RuntimeConfig.role/0) == :worker
  end

  test "rejects an invalid role" do
    assert_raise ArgumentError, ~r/invalid ROLE/, fn ->
      with_role("unknown", &RuntimeConfig.role/0)
    end
  end

  test "returns the default for an unset positive integer" do
    assert RuntimeConfig.positive_integer_env(unique_env_name(), 42) == 42
  end

  test "reads a full positive-integer override" do
    name = unique_env_name()

    with_integer_env(name, "17", fn ->
      assert RuntimeConfig.positive_integer_env(name, 42) == 17
    end)
  end

  test "rejects malformed positive-integer overrides" do
    for value <- ["0", "-3", "1.5", "12abc", "", " 5", "5 ", "abc"] do
      name = unique_env_name()

      with_integer_env(name, value, fn ->
        assert_raise ArgumentError, ~r/must be a positive integer/, fn ->
          RuntimeConfig.positive_integer_env(name, 42)
        end
      end)
    end
  end

  test "describes the offending value in the startup error" do
    name = unique_env_name()

    with_integer_env(name, "nope", fn ->
      assert_raise ArgumentError, ~r/#{name} must be a positive integer, got "nope"/, fn ->
        RuntimeConfig.positive_integer_env(name, 42)
      end
    end)
  end

  test "rejects a malformed required positive integer" do
    name = unique_env_name()

    with_integer_env(name, "0", fn ->
      assert_raise ArgumentError, ~r/must be a positive integer/, fn ->
        RuntimeConfig.positive_integer_env(name)
      end
    end)
  end

  @pilot_variables [
    "EVALUATION_PILOT_MAX_SNAPSHOT_PAYLOAD_BYTES",
    "EVALUATION_PILOT_MAX_SNAPSHOT_COMPARISONS",
    "EVALUATION_PILOT_MAX_COMPARISONS",
    "EVALUATION_PILOT_MAX_CANDIDATES",
    "EVALUATION_PILOT_MAX_PLANS_PER_SIDE",
    "EVALUATION_PILOT_MAX_ATTACK_COLUMNS",
    "EVALUATION_PILOT_MAX_WORK_ITEMS",
    "EVALUATION_PILOT_MAX_OUTER_SUBSAMPLES",
    "EVALUATION_PILOT_MAX_BOOTSTRAP_REPLICATES",
    "EVALUATION_PILOT_MAX_CANDIDATE_REQUEST_BYTES"
  ]

  @pilot_keys [
    :snapshot_payload_bytes,
    :snapshot_comparisons,
    :comparison_count,
    :candidate_count,
    :plans_per_side,
    :attack_columns,
    :work_items,
    :outer_subsamples,
    :bootstrap_replicates,
    :candidate_request_bytes
  ]

  describe "Stage 4 Pilot limits" do
    setup do
      previous = Map.new(@pilot_variables, &{&1, System.get_env(&1)})
      Enum.each(@pilot_variables, &System.delete_env/1)

      on_exit(fn ->
        Enum.each(previous, fn {name, value} ->
          if value, do: System.put_env(name, value), else: System.delete_env(name)
        end)
      end)
    end

    test "an unset set stays unconfigured" do
      assert RuntimeConfig.pilot_limits() == :unconfigured
    end

    test "a full set parses every limit" do
      @pilot_variables
      |> Enum.with_index(1)
      |> Enum.each(fn {name, value} ->
        System.put_env(name, Integer.to_string(value * 1_000))
      end)

      assert {:ok, limits} = RuntimeConfig.pilot_limits()
      assert Keyword.keys(limits) == @pilot_keys
      assert limits[:snapshot_payload_bytes] == 1_000
      assert limits[:candidate_request_bytes] == 10_000
    end

    test "a partial set is rejected" do
      System.put_env("EVALUATION_PILOT_MAX_WORK_ITEMS", "1024")

      assert {:error, message} = RuntimeConfig.pilot_limits()
      assert message =~ "set all of them or none"
    end

    test "a malformed value is rejected" do
      for {name, value} <- [
            {"EVALUATION_PILOT_MAX_COMPARISONS", "0"},
            {"EVALUATION_PILOT_MAX_WORK_ITEMS", "1.5"}
          ] do
        Enum.each(@pilot_variables, &System.put_env(&1, "16"))
        System.put_env(name, value)

        assert {:error, message} = RuntimeConfig.pilot_limits()
        assert message =~ name
        assert message =~ "must be a positive integer"
      end
    end
  end

  defp unique_env_name do
    "NETWORK_DEFENSE_RUNTIME_CONFIG_TEST_" <>
      Integer.to_string(System.unique_integer([:positive]))
  end

  @collection_variables [
    "EVALUATION_STUDY_MAX_PHASE_ITEMS",
    "EVALUATION_STUDY_MAX_GUST_CONCURRENCY"
  ]

  describe "study collection controls" do
    setup do
      previous = Map.new(@collection_variables, &{&1, System.get_env(&1)})
      Enum.each(@collection_variables, &System.delete_env/1)

      on_exit(fn ->
        Enum.each(previous, fn {name, value} ->
          if value, do: System.put_env(name, value), else: System.delete_env(name)
        end)
      end)
    end

    test "an unset control set stays unconfigured" do
      assert RuntimeConfig.study_collection_limits() == :unconfigured
    end

    test "a full control set parses both controls" do
      System.put_env("EVALUATION_STUDY_MAX_PHASE_ITEMS", "24")
      System.put_env("EVALUATION_STUDY_MAX_GUST_CONCURRENCY", "2")

      assert RuntimeConfig.study_collection_limits() ==
               {:ok, [max_phase_items: 24, max_gust_concurrency: 2]}
    end

    test "a partial control set is rejected" do
      System.put_env("EVALUATION_STUDY_MAX_PHASE_ITEMS", "24")

      assert {:error, message} = RuntimeConfig.study_collection_limits()
      assert message =~ "set all of them or none"
    end

    test "a malformed control value is rejected" do
      for {name, value} <- [
            {"EVALUATION_STUDY_MAX_PHASE_ITEMS", "0"},
            {"EVALUATION_STUDY_MAX_GUST_CONCURRENCY", "two"}
          ] do
        Enum.each(@collection_variables, &System.put_env(&1, "1"))
        System.put_env(name, value)

        assert {:error, message} = RuntimeConfig.study_collection_limits()
        assert message =~ name
        assert message =~ "must be a positive integer"
      end
    end
  end

  defp with_integer_env(name, value, fun) do
    previous = System.get_env(name)
    System.put_env(name, value)

    try do
      fun.()
    after
      if previous, do: System.put_env(name, previous), else: System.delete_env(name)
    end
  end

  defp with_role(role, fun) do
    previous = System.get_env("ROLE")

    if role, do: System.put_env("ROLE", role), else: System.delete_env("ROLE")

    try do
      fun.()
    after
      if previous, do: System.put_env("ROLE", previous), else: System.delete_env("ROLE")
    end
  end
end
