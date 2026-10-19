defmodule Mix.Tasks.Evaluation.FamilyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Ecto.Adapters.SQL.Sandbox
  alias Gust.Flows.Run
  alias Mix.Tasks.Evaluation.Family
  alias NetworkDefense.Evaluation.Family.Console
  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyRequest, FamilyResult}
  alias NetworkDefense.Evaluation.FamilyConformance
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

  test "the named valid fixture uses the console and the public family API" do
    :meck.new(Evaluations, [:passthrough, :no_link])
    on_exit(fn -> :meck.unload(Evaluations) end)
    parent = self()

    :meck.expect(Evaluations, :submit_family, fn request ->
      assert_received :console_started
      send(parent, {:submitted, request})
      {:ok, "family-run"}
    end)

    :meck.expect(Evaluations, :await_family, fn "family-run", _timeout -> {:ok, :succeeded} end)
    :meck.expect(Evaluations, :get_family_result, fn "family-run" -> {:ok, family_result!()} end)

    output = capture_io(fn -> Family.run(["--fixture", "holm-small"]) end)

    assert output =~ "Run: family-run"
    assert output =~ "Status: succeeded"
    assert output =~ "Evidence: synthetic_prototype (not Pilot or Final)"
    assert output =~ "Method: holm"
    assert output =~ "Adjusted p:"
    assert output =~ "Decision: reject the null"
    assert output =~ "not simultaneous confidence intervals"

    assert_received {:submitted, submitted}
    assert submitted == FamilyConformance.request()
  end

  test "the invalid named fixture is rejected without creating a Gust run" do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    before_count = Gust.Repo.aggregate(Run, :count)

    output =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, "family command failed", fn ->
          Family.run(["--fixture", "missing-comparison"])
        end
      end)

    assert_received :console_started
    assert output =~ "Run: not created"
    assert output =~ "missing_comparison"
    assert Gust.Repo.aggregate(Run, :count) == before_count
  end

  test "unknown fixtures and invalid arguments fail before console startup" do
    assert_raise Mix.Error, "Unknown fixture \"unknown\".", fn ->
      Family.run(["--fixture", "unknown"])
    end

    assert_raise Mix.Error, ~r/Usage: mix evaluation.family/, fn ->
      Family.run(["--unknown"])
    end

    refute_received :console_started
  end

  # The stored example is a checked-in conformance file that Python produced.
  defp family_result! do
    {:ok, request} = FamilyConformance.request() |> FamilyRequest.parse()
    {:ok, result} = FamilyResult.parse(FamilyConformance.stored_result(), request)
    result
  end
end
