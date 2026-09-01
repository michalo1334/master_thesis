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
