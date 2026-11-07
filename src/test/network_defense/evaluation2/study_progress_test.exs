defmodule NetworkDefense.Evaluation2.StudyProgressTest do
  use NetworkDefense.DataCase, async: false
  alias Ecto.Adapters.SQL.Sandbox
  alias NetworkDefense.Evaluation2.Study
  alias NetworkDefense.Evaluation2.Study.{Collection, Progress}
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.Collection, as: Store
  alias NetworkDefense.Evaluation2Test.FinalFixtures
  alias NetworkDefense.Evaluation2Test.UiFixtures
  alias NetworkDefenseWeb.StudyObserver

  setup do
    owner = Sandbox.start_owner!(Gust.Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    attrs = UiFixtures.attrs()
    c = UiFixtures.collection_context(attrs)
    %{c: c, attrs: attrs}
  end

  test "durable counters use canonical item completion, not budget callback steps", %{c: c} do
    item = hd(c.items)
    live = %{{item.id, "optimization"} => %{completed: 999, total: 999}}
    assert {:ok, before} = Progress.snapshot(c.context.execution.id, live)

    assert [
             %{completed: 0, total: 6, unit: "optimization_items"},
             %{completed: 0, total: 12, unit: "simulation_trials"}
           ] = before.counters

    assert :ok = Collection.run_optimization(item.id)
    assert {:ok, after_work} = Progress.snapshot(c.context.execution.id, live)
    assert hd(after_work.counters).completed == 1
    assert after_work.replica == 0
    refute after_work.warm_up
  end

  test "concurrent callbacks replace counters; retry attempts and unrelated executions cannot contribute",
       %{c: c, attrs: attrs} do
    [one, two | _] = c.items

    live =
      Map.new([one, two], fn item ->
        :ok = Collection.run_optimization(item.id)
        {:ok, _experiment} = Store.reserve_experiment(item.id)

        {:ok, task} =
          Gust.Flows.create_task(%{
            run_id: c.run.gust_run_id,
            name: "run_pilot_simulation",
            map_index: item.item_position,
            status: :running,
            attempt: 1,
            params: %{"collection_item_id" => item.id}
          })

        {{item.id, "experiment"},
         %{
           completed: 1,
           total: 2,
           observation_task_id: task.id,
           observation_attempt: 1,
           observation_sequence: 1
         }}
      end)

    assert {:ok, snapshot} = Progress.snapshot(c.context.execution.id, live)
    assert Enum.find(snapshot.counters, &(&1.unit == "simulation_trials")).completed == 2

    repeated =
      Enum.reduce(1..3, live, fn _, acc ->
        StudyObserver.record(acc, one.id, "experiment", live[{one.id, "experiment"}])
      end)

    assert repeated == live
    old = %{live[{one.id, "experiment"}] | completed: 2, observation_sequence: 0}
    assert StudyObserver.record(live, one.id, "experiment", old) == live
    task = Gust.Flows.get_task!(live[{one.id, "experiment"}].observation_task_id)
    Gust.Repo.update!(Ecto.Changeset.change(task, attempt: 2, status: :retrying))
    assert {:ok, retry} = Progress.snapshot(c.context.execution.id, live)
    assert Enum.find(retry.counters, &(&1.unit == "simulation_trials")).completed == 1
    assert retry.activity =~ "Retrying"
    other = UiFixtures.collection_context(attrs)
    assert {:ok, isolated} = Progress.snapshot(other.context.execution.id, live)
    assert Enum.all?(isolated.counters, &(&1.completed == 0))
    assert :ok = Collection.run_simulation(two.id)
    assert {:ok, durable} = Study.progress(c.context.execution.id)
    assert Enum.find(durable.counters, &(&1.unit == "simulation_trials")).completed == 2
  end

  test "observer presents ordered watch-scoped snapshots and never advances lifecycle", %{c: c} do
    execution_id = c.context.execution.id

    {:ok, observer} =
      StudyObserver.start_link(
        owner: self(),
        execution_id: execution_id,
        document_id: "doc",
        watch_id: "watch"
      )

    on_exit(fn -> if Process.alive?(observer), do: GenServer.stop(observer) end)

    assert_receive {:study_observed,
                    %{watch_id: "watch", sequence: 1, status: %{state: "collecting_pilot"}}},
                   1_000

    send(
      observer,
      {:optimization_progress,
       %{correlation_id: "#{hd(c.items).id}/optimization", completed: 100, total: 100}}
    )

    assert_receive {:study_observed,
                    %{watch_id: "watch", sequence: sequence, progress: progress}},
                   1_500

    assert sequence > 1
    assert hd(progress.counters).completed == 0
    assert {:ok, %{state: :collecting_pilot}} = Study.status(execution_id)
    assert {:ok, %{state: :cancelled}} = Study.cancel(execution_id)
    assert_receive {:study_observed, %{status: %{state: "cancelled"}}}, 1_500
    assert_receive {:study_observed, %{status: %{state: "cancelled"}}}, 1_500
  end

  test "Final scope labels warm-up separately and resets counters for each measured replica" do
    c = FinalFixtures.approved_context()
    id = Ecto.UUID.generate()
    {:ok, dag} = Gust.Flows.create_dag(%{name: "evaluation2_study_final_tier_collection"})

    {:ok, gust_run} =
      Gust.Flows.create_run(%{dag_id: dag.id, params: %{"study_phase_run_id" => id}})

    {:ok, run} = Persistence.link_phase_run(c.active_phase.id, :small, id, gust_run.id)

    {:ok, plan} =
      Collection.prepare_final(run.id, c.revision.definition, c.execution.selection, :small)

    {:ok, _items} = Collection.prepare_replica(plan.id, -1)
    assert {:ok, %{warm_up: true, replica: -1, tier: "small"}} = Study.progress(c.execution.id)
    {:ok, _items} = Collection.prepare_replica(plan.id, 0)
    assert {:ok, measured} = Study.progress(c.execution.id)
    refute measured.warm_up
    assert measured.replica == 0
    assert Enum.all?(measured.counters, &(&1.completed == 0))
  end

  test "owner exit releases its observer even on a normal disconnect", %{c: c} do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, observer} =
          StudyObserver.start_link(
            owner: self(),
            execution_id: c.context.execution.id,
            document_id: "owned",
            watch_id: "owned"
          )

        send(parent, {:observer, observer})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:observer, observer}, 1_000
    monitor = Process.monitor(observer)
    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^observer, :normal}, 1_000
  end

  test "UI publication preserves the simulation callback stop contract", %{c: c} do
    item = hd(c.items)
    assert :ok = Collection.run_optimization(item.id)
    assert {:ok, experiment} = Store.reserve_experiment(item.id)

    assert {:error, :cancelled} =
             NetworkDefense.Simulations.run(experiment.id,
               correlation_id: "#{item.id}/experiment",
               publish_events: true,
               on_progress: fn _progress -> {:error, :cancelled} end
             )
  end

  test "publication tolerates an unavailable PubSub" do
    assert :ok =
             NetworkDefense.ProgressPublication.broadcast(
               :absent_pubsub,
               "topic",
               {:progress, %{completed: 1}}
             )
  end
end
