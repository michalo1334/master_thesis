defmodule Mix.PrecommitCredoTest do
  # Precommit state is global Mix state and inherited OS environment, so these
  # cases must not run beside asynchronous tests.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias NetworkDefense.MixProject

  @moduletag :tmp_dir

  @observed_variables ["MIX_ENV", "MIX_TARGET", "MIX_TEST_PARTITION"]

  setup do
    saved = %{
      env: Mix.env(),
      target: Mix.target(),
      os: Map.new(@observed_variables, &{&1, System.get_env(&1)})
    }

    on_exit(fn ->
      Mix.env(saved.env)
      Mix.target(saved.target)
      Enum.each(saved.os, fn {name, value} -> restore_variable(name, value) end)
    end)

    :ok
  end

  test "PRECOMMIT-CREDO-01: alias keeps the isolated Credo step and every other step" do
    steps = Mix.Project.config()[:aliases][:precommit]
    credo_step = &MixProject.credo/1

    assert credo_step in steps
    index = Enum.find_index(steps, &(&1 == credo_step))

    assert Enum.at(steps, index - 1) == "assets.build"
    assert Enum.at(steps, index + 1) == "dialyzer"

    assert Enum.reject(steps, &(&1 == credo_step)) == [
             "compile --warning-as-errors",
             "gen.contracts",
             "format --check-formatted",
             "cmd npm run format:check",
             "cmd npm run typecheck",
             "assets.build",
             "dialyzer",
             "sobelow --config --skip",
             "deps.unlock --unused",
             "test"
           ]

    assert MixProject.credo_command() == {"mix", ["credo", "--strict"]}
  end

  test "PRECOMMIT-CREDO-02: child observes the selected env and target when neither is exported",
       %{tmp_dir: tmp_dir} do
    clear_environment()
    Mix.env(:test)
    Mix.target(:review_target)

    assert observe_child(tmp_dir) == %{
             "MIX_ENV" => "test",
             "MIX_TARGET" => "review_target",
             "MIX_TEST_PARTITION" => nil
           }
  end

  test "PRECOMMIT-CREDO-03: child preserves exported env and target variables",
       %{tmp_dir: tmp_dir} do
    System.put_env("MIX_ENV", "test")
    System.put_env("MIX_TARGET", "host")
    Mix.env(:test)
    Mix.target(:host)

    assert %{"MIX_ENV" => "test", "MIX_TARGET" => "host"} = observe_child(tmp_dir)
  end

  test "PRECOMMIT-CREDO-04: active project state wins over a stale exported variable",
       %{tmp_dir: tmp_dir} do
    System.put_env("MIX_ENV", "dev")
    System.put_env("MIX_TARGET", "stale_target")
    Mix.env(:test)
    Mix.target(:review_target)

    assert %{"MIX_ENV" => "test", "MIX_TARGET" => "review_target"} = observe_child(tmp_dir)
  end

  test "PRECOMMIT-CREDO-05: child inherits the test partition of the parent",
       %{tmp_dir: tmp_dir} do
    System.put_env("MIX_TEST_PARTITION", "implicit_env_fix_probe")
    Mix.env(:test)
    Mix.target(:host)

    assert %{"MIX_TEST_PARTITION" => "implicit_env_fix_probe"} = observe_child(tmp_dir)
  end

  test "PRECOMMIT-CREDO-06: nonzero child status fails the parent check" do
    assert_raise Mix.Error, ~r/exit status 3/, fn ->
      MixProject.run_isolated(elixir(), ["-e", "System.halt(3)"])
    end
  end

  test "PRECOMMIT-CREDO-07: Credo still executes after earlier cmd steps ran" do
    Mix.Task.run("cmd", ["true"])
    on_exit(fn -> Mix.Task.reenable("cmd") end)

    {result, output} = with_io(fn -> MixProject.credo([]) end)

    assert result == :ok
    assert output =~ "Checking"
  end

  defp observe_child(tmp_dir) do
    observation_path = Path.join(tmp_dir, "child_environment.term")

    script = """
    observed =
      Enum.map(#{inspect(@observed_variables)}, fn name -> {name, System.get_env(name)} end)

    File.write!(#{inspect(observation_path)}, :erlang.term_to_binary(observed))
    """

    :ok = MixProject.run_isolated(elixir(), ["-e", script])

    observation_path
    |> File.read!()
    |> :erlang.binary_to_term()
    |> Map.new()
  end

  defp clear_environment, do: Enum.each(@observed_variables, &System.delete_env/1)

  defp restore_variable(name, nil), do: System.delete_env(name)
  defp restore_variable(name, value), do: System.put_env(name, value)

  defp elixir, do: System.find_executable("elixir") || raise("the elixir executable is missing")
end
