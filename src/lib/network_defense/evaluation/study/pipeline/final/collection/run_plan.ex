defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.RunPlan do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.{ConcurrencyGate, Runner}
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO
  alias NetworkDefense.Evaluation.StudyCollectionItem

  # One mapped plan-selection item.
  #
  # The stored item row is the input, so the work stays canonical and repeatable.
  # The gate keeps the deployment-wide concurrency cap around the effect.
  @spec run(IO.Item.t()) :: {:ok, IO.Item.t()} | {:error, StudyError.t()}
  def run(%IO.Item{collection_item_id: collection_item_id} = item) do
    case ConcurrencyGate.run(fn -> Runner.run_plan_selection_item(collection_item_id) end) do
      {:ok, %StudyCollectionItem{} = stored} -> {:ok, %{item | collection_item: stored}}
      {:error, %StudyError{} = error} -> {:error, error}
      _unexpected -> {:error, StudyError.collection_item_not_found()}
    end
  end

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.RunPlan

    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO
    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter

    @impl GustAdapter
    def decode(args, _context) when is_list(args), do: IO.Item.load_from_args(args)

    @impl GustAdapter
    def encode(%IO.Item{collection_item_id: collection_item_id}) do
      %{"collection_item_id" => collection_item_id}
    end
  end
end
