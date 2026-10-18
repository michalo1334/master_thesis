defmodule Mix.Tasks.Evaluation.CompareTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.Flows.Run
  alias Mix.Tasks.Evaluation.Compare
  alias NetworkDefense.Evaluation.Comparison.Console
  alias NetworkDefense.Evaluation.Comparison.Contracts.{ComparisonRequest, ComparisonStatistics}
  alias NetworkDefense.Evaluations

  setup do
    :meck.new(Console, [:passthrough, :no_link])
    parent = self()

    :meck.expect(Console, :start!, fn ->
      send(parent, :console_started)
      :ok
    end)

    on_exit(fn -> :meck.unload(Console) end)
    :ok
  end

  test "the named valid fixture uses the console and existing evaluation APIs" do
    :meck.new(Evaluations, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(Evaluations) end)
    parent = self()

    :meck.expect(Evaluations, :submit_comparison, fn request ->
      assert_received :console_started
      send(parent, {:submitted, request})
      {:ok, "console-run"}
    end)

    :meck.expect(Evaluations, :await_comparison, fn "console-run", _timeout ->
      {:ok, :succeeded}
    end)

    statistics =
      :network_defense
      |> Application.app_dir("priv/evaluation/contracts/v1/valid/informative.statistics.json")
      |> File.read!()
      |> Jason.decode!()

    {:ok, request} =
      "crossed-small"
      |> Console.fixture_path!()
      |> File.read!()
      |> Jason.decode!()
      |> ComparisonRequest.parse()

    {:ok, result} = ComparisonStatistics.parse(statistics, request)
    :meck.expect(Evaluations, :get_comparison_result, fn "console-run" -> {:ok, result} end)

    output = capture_io(fn -> Compare.run(["--fixture", "crossed-small"]) end)
    assert output =~ "Run: console-run"
    assert output =~ "Status: succeeded"
    assert_received {:submitted, submitted}

    assert submitted ==
             Console.fixture_path!("crossed-small") |> File.read!() |> Jason.decode!()
  end

  test "the invalid named fixture is rejected without creating a Gust run" do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    before_count = Gust.Repo.aggregate(Run, :count)

    output =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, "comparison command failed", fn ->
          Compare.run(["--fixture", "attack-column-count-mismatch"])
        end
      end)

    assert_received :console_started
    assert output =~ "attack_column_count_mismatch"
    assert Gust.Repo.aggregate(Run, :count) == before_count
  end

  test "unknown fixtures and invalid arguments fail before console startup" do
    assert_raise Mix.Error, "Unknown fixture \"unknown\".", fn ->
      Compare.run(["--fixture", "unknown"])
    end

    assert_raise Mix.Error, ~r/Usage: mix evaluation.compare/, fn ->
      Compare.run(["--unknown"])
    end

    refute_received :console_started
  end
end
