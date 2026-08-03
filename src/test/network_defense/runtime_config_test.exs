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
end
