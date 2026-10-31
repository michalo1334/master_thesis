defmodule NetworkDefense.Evaluation2.Study.Persistence.Collection do
  @moduledoc false

  # Collection plans, replica items, and the two retry-safe effect links.
  #
  # A plan holds the complete resolved request list of one phase run, so every
  # replica of that run reuses one immutable plan. One item row is one replica
  # coordinate and owns the optimization run and the simulation experiment that a
  # retried Gust task reuses.
  #
  # Composite writes are short transactions. A plan or item row lock serializes
  # two attempts, so the loser reads the stored record instead of creating a
  # second one.

  import Ecto.Query

  alias Ecto.Changeset
  alias NetworkDefense.Evaluation2.Study.Collection.WorkItem
  alias NetworkDefense.Evaluation2.Study.Persistence
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionItem
  alias NetworkDefense.Evaluation2.Study.Persistence.CollectionPlan
  alias NetworkDefense.Optimization.OptimizationRun
  alias NetworkDefense.Optimization.OptimizationRuns
  alias NetworkDefense.Optimizations
  alias NetworkDefense.Repo
  alias NetworkDefense.Simulation.Experiment
  alias NetworkDefense.Simulation.Experiments
  alias NetworkDefense.Simulations

  # Replica positions of one planned work set: warm-up and measured replicas.
  @replica_positions -1..4

  # --- plans ---------------------------------------------------------------

  # The stored JSONB object is one `CollectionPlan.payload()` value. An equal
  # retry returns the stored plan and a different list conflicts.
  @spec insert_collection_plan(Ecto.UUID.t(), [WorkItem.t()]) ::
          Persistence.response(CollectionPlan.t())
  def insert_collection_plan(phase_run_id, work_items) do
    with {:ok, uuid} <- Persistence.cast_id(phase_run_id, :insert_collection_plan, :phase_run),
         :ok <- complete_work_items(work_items, :insert_collection_plan),
         {:ok, params} <-
           Persistence.encode_json(
             CollectionPlan,
             :payload,
             %{items: work_items},
             :insert_collection_plan,
             :collection_plan
           ) do
      Persistence.contain(:insert_collection_plan, :collection_plan, fn ->
        plan_for_run(uuid, work_items, params, :insert_collection_plan)
      end)
    end
  end

  defp plan_for_run(phase_run_id, work_items, params, operation) do
    with {:ok, _phase_run} <- Persistence.stored_phase_run(phase_run_id, operation) do
      insert_plan_once(phase_run_id, work_items, params, operation)
    end
  end

  # A stored plan is the complete resolved request of every item, so an incomplete
  # request is rejected before it reaches durable storage.
  defp complete_work_items(work_items, operation) do
    if Enum.all?(work_items, &complete_work_item?/1) do
      :ok
    else
      {:error, Persistence.error(:storage, operation, :collection_plan, :incomplete_work_item)}
    end
  end

  defp complete_work_item?(%WorkItem{initial_foothold_node_id: foothold})
       when is_binary(foothold),
       do: true

  defp complete_work_item?(_work_item), do: false

  @spec fetch_collection_plan(Ecto.UUID.t()) :: Persistence.response(CollectionPlan.t())
  def fetch_collection_plan(phase_run_id) do
    with {:ok, uuid} <- Persistence.cast_id(phase_run_id, :fetch_collection_plan, :phase_run) do
      query = from p in CollectionPlan, where: p.study_phase_run_id == ^uuid

      Persistence.fetch_one(:fetch_collection_plan, :collection_plan, query, fn plan ->
        decode_plan(plan, :fetch_collection_plan)
      end)
    end
  end

  defp insert_plan_once(run_id, work_items, params, operation) do
    %CollectionPlan{study_phase_run_id: run_id, items: params}
    |> Changeset.change()
    |> Changeset.unique_constraint(:study_phase_run_id,
      name: :evaluation2_collection_plans_study_phase_run_id_index
    )
    |> Repo.insert()
    |> case do
      {:ok, plan} -> decode_plan(plan, operation)
      {:error, changeset} -> stored_plan_result(changeset, run_id, work_items, operation)
    end
  end

  defp stored_plan_result(changeset, run_id, work_items, operation) do
    if Persistence.unique_conflict?(changeset) do
      compare_stored_plan(run_id, work_items, operation)
    else
      {:error, Persistence.error(:storage, operation, :collection_plan, changeset)}
    end
  end

  defp compare_stored_plan(run_id, work_items, operation) do
    case Repo.get_by(CollectionPlan, study_phase_run_id: run_id) do
      nil ->
        {:error,
         Persistence.error(:storage, operation, :collection_plan, :missing_after_conflict)}

      plan ->
        compare_plan_items(plan, work_items, operation)
    end
  end

  defp compare_plan_items(plan, work_items, operation) do
    with {:ok, stored} <- decode_plan(plan, operation) do
      if stored.items == work_items do
        {:ok, stored}
      else
        {:error, Persistence.error(:conflict, operation, :collection_plan, :different_payload)}
      end
    end
  end

  # --- items ---------------------------------------------------------------

  # The plan row lock serializes two preparations of the same replica, so the
  # complete ordered set exists once.
  @spec prepare_collection_items(Ecto.UUID.t(), CollectionItem.replica_position()) ::
          Persistence.response([CollectionItem.t()])
  def prepare_collection_items(plan_id, replica_position) do
    with {:ok, uuid} <- Persistence.cast_id(plan_id, :prepare_collection_items, :collection_plan),
         :ok <- expect_replica_position(replica_position, :prepare_collection_items) do
      Persistence.tx(:prepare_collection_items, :collection_item, fn ->
        prepared_items(uuid, replica_position, :prepare_collection_items)
      end)
    end
  end

  defp prepared_items(plan_id, replica_position, operation) do
    with {:ok, plan} <- lock_plan(plan_id, operation),
         {:ok, decoded} <- decode_plan(plan, operation) do
      prepare_replica_items(
        plan.study_phase_run_id,
        replica_position,
        length(decoded.items),
        operation
      )
    end
  end

  @spec fetch_collection_item(Ecto.UUID.t()) :: Persistence.response(CollectionItem.t())
  def fetch_collection_item(item_id) do
    with {:ok, uuid} <- Persistence.cast_id(item_id, :fetch_collection_item, :collection_item) do
      query = from i in CollectionItem, where: i.id == ^uuid

      Persistence.fetch_one(:fetch_collection_item, :collection_item, query, &{:ok, &1})
    end
  end

  @spec list_replica_items(Ecto.UUID.t(), CollectionItem.replica_position()) ::
          Persistence.response([CollectionItem.t()])
  def list_replica_items(phase_run_id, replica_position) do
    with {:ok, uuid} <- Persistence.cast_id(phase_run_id, :list_replica_items, :phase_run),
         :ok <- expect_replica_position(replica_position, :list_replica_items) do
      Persistence.read(:list_replica_items, :collection_item, fn ->
        replica_items(uuid, replica_position)
      end)
    end
  end

  defp prepare_replica_items(run_id, replica_position, count, operation) do
    items = replica_items(run_id, replica_position)

    cond do
      items == [] ->
        insert_replica_items(run_id, replica_position, count, operation)

      complete_positions?(items, count) ->
        {:ok, items}

      true ->
        {:error, Persistence.error(:storage, operation, :collection_item, :incomplete_replica)}
    end
  end

  defp replica_items(run_id, replica_position) do
    Repo.all(
      from i in CollectionItem,
        where: i.study_phase_run_id == ^run_id and i.replica_position == ^replica_position,
        order_by: i.item_position
    )
  end

  defp complete_positions?(items, count) do
    length(items) == count and Enum.map(items, & &1.item_position) == positions(count)
  end

  defp insert_replica_items(run_id, replica_position, count, operation) do
    Enum.reduce_while(positions(count), [], fn position, inserted ->
      case Repo.insert(%CollectionItem{
             study_phase_run_id: run_id,
             replica_position: replica_position,
             item_position: position
           }) do
        {:ok, %CollectionItem{} = item} -> {:cont, [item | inserted]}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:error, changeset} ->
        {:error, Persistence.error(:storage, operation, :collection_item, changeset)}

      items ->
        {:ok, Enum.reverse(items)}
    end
  end

  defp positions(count), do: Enum.to_list(0..(count - 1)//1)

  defp expect_replica_position(position, _operation) when position in @replica_positions, do: :ok

  defp expect_replica_position(_position, operation) do
    {:error, Persistence.error(:storage, operation, :collection_item, :invalid_replica_position)}
  end

  # --- effect reservations -------------------------------------------------

  # The item lock and the create-or-reuse transaction make a retry return the
  # linked record instead of a second one. The planned request is the only input,
  # so a caller cannot supply a second request representation.
  @spec reserve_optimization(Ecto.UUID.t()) :: Persistence.response(OptimizationRun.t())
  def reserve_optimization(item_id) do
    with {:ok, uuid} <- Persistence.cast_id(item_id, :reserve_optimization, :collection_item) do
      Persistence.tx(:reserve_optimization, :collection_item, fn ->
        reserved_optimization(uuid, :reserve_optimization)
      end)
    end
  end

  # The experiment consumes the optimization run already linked by the item, so a
  # retry of the simulation stage reuses one experiment.
  @spec reserve_experiment(Ecto.UUID.t()) :: Persistence.response(Experiment.t())
  def reserve_experiment(item_id) do
    with {:ok, uuid} <- Persistence.cast_id(item_id, :reserve_experiment, :collection_item) do
      Persistence.tx(:reserve_experiment, :collection_item, fn ->
        reserved_experiment(uuid, :reserve_experiment)
      end)
    end
  end

  defp reserved_optimization(item_id, operation) do
    with {:ok, item} <- lock_item(item_id, operation) do
      optimization_for_item(item, operation)
    end
  end

  defp reserved_experiment(item_id, operation) do
    with {:ok, item} <- lock_item(item_id, operation) do
      experiment_for_item(item, operation)
    end
  end

  defp optimization_for_item(%CollectionItem{optimization_run_id: nil} = item, operation) do
    with {:ok, work_item} <- planned_work_item(item, operation),
         {:ok, candidate} <- optimization_candidate(item, work_item, operation),
         {:ok, run} <- insert_optimization(candidate, operation),
         {:ok, _item} <- link_effect(item, %{optimization_run_id: run.id}, operation) do
      {:ok, run}
    end
  end

  defp optimization_for_item(%CollectionItem{} = item, operation),
    do: linked_optimization(item, operation)

  defp experiment_for_item(%CollectionItem{experiment_id: nil} = item, operation) do
    with {:ok, run} <- linked_optimization(item, operation),
         {:ok, work_item} <- planned_work_item(item, operation),
         {:ok, candidate} <-
           experiment_candidate(item, work_item, run, operation),
         {:ok, experiment} <- insert_experiment(candidate, operation),
         {:ok, _item} <- link_effect(item, %{experiment_id: experiment.id}, operation) do
      {:ok, experiment}
    end
  end

  defp experiment_for_item(%CollectionItem{experiment_id: experiment_id}, operation) do
    case Repo.get(Experiment, experiment_id) do
      %Experiment{} = experiment -> {:ok, experiment}
      nil -> {:error, Persistence.error(:storage, operation, :experiment, :linked_record_missing)}
    end
  end

  defp linked_optimization(%CollectionItem{optimization_run_id: nil}, operation) do
    {:error, Persistence.error(:storage, operation, :optimization_run, :not_reserved)}
  end

  defp linked_optimization(%CollectionItem{optimization_run_id: run_id}, operation) do
    case Repo.get(OptimizationRun, run_id) do
      %OptimizationRun{} = run ->
        {:ok, run}

      nil ->
        {:error,
         Persistence.error(:storage, operation, :optimization_run, :linked_record_missing)}
    end
  end

  defp planned_work_item(
         %CollectionItem{study_phase_run_id: run_id, item_position: position},
         operation
       ) do
    with {:ok, plan} <- stored_plan(run_id, operation) do
      case Enum.at(plan.items, position) do
        %WorkItem{} = work_item ->
          {:ok, work_item}

        nil ->
          {:error,
           Persistence.error(:storage, operation, :collection_item, :position_out_of_range)}
      end
    end
  end

  defp optimization_candidate(item, work_item, operation) do
    case Optimizations.prepare_candidate(optimization_request(item, work_item)) do
      {:ok, _graph, %OptimizationRun{} = candidate} ->
        {:ok, candidate}

      {:error, reason} ->
        {:error, Persistence.error(:storage, operation, :optimization_run, {:rejected, reason})}
    end
  end

  defp insert_optimization(candidate, operation) do
    case OptimizationRuns.create(candidate) do
      {:ok, %OptimizationRun{} = run} ->
        {:ok, run}

      {:error, changeset} ->
        {:error, Persistence.error(:storage, operation, :optimization_run, changeset)}
    end
  end

  defp experiment_candidate(item, work_item, run, operation) do
    if is_binary(run.output_graph_revision_id) and run.output_graph_revision_id != "" do
      prepare_experiment(item, work_item, run, operation)
    else
      {:error, Persistence.error(:storage, operation, :optimization_run, :incomplete)}
    end
  end

  defp prepare_experiment(item, work_item, run, operation) do
    case Simulations.prepare_candidate(simulation_request(item, work_item, run)) do
      {:ok, %Experiment{} = candidate} ->
        {:ok, candidate}

      {:error, reason} ->
        {:error, Persistence.error(:storage, operation, :experiment, {:rejected, reason})}
    end
  end

  defp insert_experiment(candidate, operation) do
    case Experiments.create(candidate) do
      {:ok, %Experiment{} = experiment} ->
        {:ok, experiment}

      {:error, changeset} ->
        {:error, Persistence.error(:storage, operation, :experiment, changeset)}
    end
  end

  defp link_effect(item, changes, operation) do
    case item |> Changeset.change(changes) |> Repo.update() do
      {:ok, %CollectionItem{} = updated} ->
        {:ok, updated}

      {:error, changeset} ->
        {:error, Persistence.error(:storage, operation, :collection_item, changeset)}
    end
  end

  defp optimization_request(item, work),
    do: WorkItem.optimization_request(work, correlation_id(item, :optimization))

  defp simulation_request(item, work, run),
    do:
      WorkItem.simulation_request(
        work,
        run.output_graph_revision_id,
        correlation_id(item, :experiment)
      )

  defp correlation_id(%CollectionItem{id: id}, step), do: "#{id}/#{step}"

  # --- private record helpers ----------------------------------------------

  defp lock_plan(uuid, operation) do
    case Repo.one(from p in CollectionPlan, where: p.id == ^uuid, lock: "FOR UPDATE") do
      %CollectionPlan{} = plan -> {:ok, plan}
      nil -> {:error, Persistence.error(:not_found, operation, :collection_plan, nil)}
    end
  end

  defp lock_item(uuid, operation) do
    case Repo.one(from i in CollectionItem, where: i.id == ^uuid, lock: "FOR UPDATE") do
      %CollectionItem{} = item -> {:ok, item}
      nil -> {:error, Persistence.error(:not_found, operation, :collection_item, nil)}
    end
  end

  defp stored_plan(run_id, operation) do
    case Repo.get_by(CollectionPlan, study_phase_run_id: run_id) do
      %CollectionPlan{} = plan -> decode_plan(plan, operation)
      nil -> {:error, Persistence.error(:not_found, operation, :collection_plan, nil)}
    end
  end

  # The stored object has the ordered item list under one key, because an Ecto
  # `:map` field holds one JSON object per column.
  defp decode_plan(%CollectionPlan{} = plan, operation) do
    case Persistence.decode_json(
           CollectionPlan,
           :payload,
           plan.items,
           operation,
           :collection_plan
         ) do
      {:ok, %{items: items}} when is_list(items) ->
        {:ok, %{plan | items: items}}

      {:ok, _payload} ->
        {:error,
         Persistence.error(:corrupt_data, operation, :collection_plan, :unexpected_payload)}

      {:error, failure} ->
        {:error, failure}
    end
  end
end
