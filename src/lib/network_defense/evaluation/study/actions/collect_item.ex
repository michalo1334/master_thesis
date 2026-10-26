defmodule NetworkDefense.Evaluation.Study.Actions.CollectItem do
  @moduledoc false
  @behaviour Gust.Action

  alias NetworkDefense.Evaluation.Study.Collection
  alias NetworkDefense.Evaluation.Study.Contracts.{CollectionResult, StudyError}

  # The task payload carries one stable collection-item identifier and nothing
  # else.

  @impl true
  def execute(args, _context) do
    with {:ok, collection_item_id} <- collection_item_id(args),
         {:ok, %CollectionResult{} = result} <- Collection.run_collection_item(collection_item_id) do
      CollectionResult.to_params(result)
    else
      {:error, %StudyError{} = error} -> raise_permanent(error)
      :error -> raise_permanent(StudyError.collection_item_not_found())
    end
  end

  defp collection_item_id(args) do
    case Keyword.fetch(args, :collection_item_id) do
      {:ok, value} -> Ecto.UUID.cast(value)
      :error -> :error
    end
  end

  # Only bounded codes reach the persisted task error.
  defp raise_permanent(%StudyError{code: code, issues: issues}) do
    codes = issues |> Enum.map(&Map.get(&1, "code")) |> Enum.reject(&is_nil/1)
    raise Gust.DAG.NonRecError, Jason.encode!(%{"code" => code, "issues" => codes})
  end
end
