defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.RunPlan do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.ConcurrencyGate
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Runner
  alias NetworkDefense.Evaluation.Study.Pipeline.Failure

  @impl true
  def execute(args, _context) do
    with {:ok, collection_item_id} <- collection_item_id(args),
         {:ok, item} <-
           ConcurrencyGate.run(fn ->
             Runner.run_plan_selection_item(collection_item_id)
           end) do
      %{"collection_item_id" => item.id}
    else
      {:error, %StudyError{} = error} -> Failure.raise_permanent(error)
      :error -> Failure.raise_permanent(StudyError.collection_item_not_found())
    end
  end

  defp collection_item_id(args) do
    case Keyword.fetch(args, :collection_item_id) do
      {:ok, value} -> Ecto.UUID.cast(value)
      :error -> :error
    end
  end
end
