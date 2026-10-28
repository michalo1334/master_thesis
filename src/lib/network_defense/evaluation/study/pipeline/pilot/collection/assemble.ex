defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Assemble do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Planner
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.{FanIn, IO, Snapshot}

  @prepare_task "prepare_pilot_collection"
  @collection_task "collect_pilot_item"
  @replica_position 0

  @spec run(IO.t()) :: {:ok, IO.t()} | {:error, StudyError.t()}
  def run(%IO{gust_run: %{id: run_id}} = io) do
    with {:ok, work} <-
           Planner.build_collection_work(
             io.execution,
             io.phase,
             io.definition,
             @replica_position
           ),
         {:ok, items} <- load_items(io, work, run_id),
         {:ok, snapshot_id} <-
           Snapshot.assemble_and_store_pilot_snapshot(io.phase, items, io.definition) do
      {:ok,
       %{
         io
         | work: work,
           items: Enum.map(items, &%IO.Item{collection_item_id: &1.id}),
           snapshot_id: snapshot_id
       }}
    end
  end

  def run(%IO{}), do: {:error, StudyError.collection_workflow_failed()}

  # The fan-in reloads stored items and proves the mapped tasks agree with them.
  defp load_items(%IO{} = io, work, run_id) do
    case FanIn.load_items(io.phase, work, run_id, @prepare_task, @collection_task) do
      {:ok, items} -> {:ok, items}
      :error -> {:error, StudyError.incomplete_pilot_evidence(["collection_items"])}
    end
  end

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Assemble

    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter
    alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.IO

    @impl GustAdapter
    def decode(_args, %{run_id: run_id}), do: IO.load_from_gust_run(run_id)

    @impl GustAdapter
    def encode(%IO{snapshot_id: snapshot_id}), do: %{"snapshot_id" => snapshot_id}
  end
end
