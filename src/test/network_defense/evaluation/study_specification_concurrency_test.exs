defmodule NetworkDefense.Evaluation.StudySpecificationConcurrencyTest do
  use NetworkDefense.DataCase, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias NetworkDefense.Evaluation.StudySpecification
  alias NetworkDefense.Evaluation.StudySpecifications
  alias NetworkDefense.EvaluationFixtures

  defp specification(overrides \\ %{}) do
    EvaluationFixtures.study_specification()
    |> Map.put("study_id", "study-#{System.unique_integer([:positive])}")
    |> Map.merge(overrides)
  end

  test "resolves identical concurrent saves to one immutable version" do
    spec = specification()
    on_exit(fn -> delete_specifications(spec["study_id"]) end)

    results =
      race([
        fn -> save(spec) end,
        fn -> save(spec) end,
        fn -> save(spec) end,
        fn -> save(spec) end
      ])

    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert results |> Enum.map(fn {:ok, saved} -> saved.id end) |> Enum.uniq() |> length() == 1
    assert [_single] = StudySpecifications.list_versions(spec["study_id"])
  end

  test "rejects one of two conflicting concurrent saves" do
    spec = specification()
    changed = Map.put(spec, "tiers", ["small"])
    on_exit(fn -> delete_specifications(spec["study_id"]) end)

    results = race([fn -> save(spec) end, fn -> save(changed) end])

    assert {:ok, saved} = Enum.find(results, &match?({:ok, _}, &1))
    assert {:error, :immutable_conflict} = Enum.find(results, &match?({:error, _}, &1))
    assert [_single] = StudySpecifications.list_versions(spec["study_id"])
    assert StudySpecifications.get(saved.id).content == saved.content
  end

  defp save(content), do: EvaluationFixtures.save_study_specification(content)

  # Runs each function on its own database connection. Every function checks
  # out a connection, signals readiness, then blocks on one shared start
  # signal. All writes therefore reach the unique index together instead of
  # serializing on the test's shared sandbox connection.
  defp race(funs) do
    parent = self()
    tasks = Enum.map(funs, &run_in_task(&1, parent))
    ready = for _fun <- funs, do: await_ready()

    assert ready |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == length(funs)
    Enum.each(ready, fn {pid, _backend} -> send(pid, :go) end)
    Task.await_many(tasks, 10_000)
  end

  defp run_in_task(fun, parent) do
    Task.async(fn ->
      on_own_connection(fn ->
        send(parent, {:ready, self(), backend_pid()})
        await_go()
        fun.()
      end)
    end)
  end

  defp await_ready do
    receive do
      {:ready, pid, backend} -> {pid, backend}
    after
      5_000 -> raise "study specification race did not synchronize"
    end
  end

  defp backend_pid do
    %{rows: [[pid]]} = Repo.query!("select pg_backend_pid()")
    pid
  end

  defp await_go do
    receive do
      :go -> :ok
    after
      5_000 -> raise "study specification race did not start"
    end
  end

  # Runs one function on a real connection outside the test sandbox
  # transaction so its writes commit and race on the unique index.
  defp on_own_connection(fun) do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    try do
      fun.()
    after
      Sandbox.checkin(Repo)
    end
  end

  defp delete_specifications(study_id) do
    Task.async(fn ->
      on_own_connection(fn ->
        Repo.delete_all(
          from specification in StudySpecification, where: specification.study_id == ^study_id
        )
      end)
    end)
    |> Task.await(5_000)
  end
end
