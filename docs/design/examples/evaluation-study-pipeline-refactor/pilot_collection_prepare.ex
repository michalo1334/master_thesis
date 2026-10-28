defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Prepare do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.{ItemStore, Planner}
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.IO

  @spec run(IO.t()) :: {:ok, IO.t()} | {:error, term()}
  def run(%IO{} = io) do
    with {:ok, work} <- Planner.plan(io.execution, io.stage, io.definition),
         {:ok, items} <- ItemStore.create_all(io.stage, work) do
      {:ok, %{io | work: work, items: items}}
    end
  end

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Prepare

    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter
    alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.IO

    @impl GustAdapter
    def decode(_args, %{run_id: run_id}), do: IO.load_from_gust_run(run_id)

    @impl GustAdapter
    def encode(%IO{items: items}) do
      %{
        "gust_task_items" => Enum.map(items, &%{"collection_item_id" => &1.id})
      }
    end
  end
end
