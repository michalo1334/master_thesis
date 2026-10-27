defmodule NetworkDefense.Evaluation.Study.Actions.RunFinalSimulationItem do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Study.{Collection, CollectionConcurrencyGate, TaskFailure}
  alias NetworkDefense.Evaluation.Study.Contracts.{CollectionResult, StudyError}

  @impl true
  def execute(args, _context) do
    with {:ok, collection_item_id} <- collection_item_id(args),
         {:ok, %CollectionResult{} = result} <-
           CollectionConcurrencyGate.run(fn ->
             Collection.run_simulation_item(collection_item_id)
           end) do
      CollectionResult.to_params(result)
    else
      {:error, %StudyError{} = error} -> TaskFailure.raise_permanent(error)
      :error -> TaskFailure.raise_permanent(StudyError.collection_item_not_found())
    end
  end

  defp collection_item_id(args) do
    case Keyword.fetch(args, :collection_item_id) do
      {:ok, value} -> Ecto.UUID.cast(value)
      :error -> :error
    end
  end
end
