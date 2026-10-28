defmodule NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Collect do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.{ConcurrencyGate, Receipt}
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Runner
  alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.IO

  @spec run(IO.Item.t()) :: {:ok, IO.Item.t()} | {:error, StudyError.t()}
  def run(%IO.Item{collection_item_id: collection_item_id} = item)
      when is_binary(collection_item_id) do
    with {:ok, %Receipt{} = receipt} <-
           ConcurrencyGate.run(fn ->
             Runner.run_collection_item(collection_item_id)
           end) do
      {:ok, %{item | receipt: receipt}}
    end
  end

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.Collect

    alias NetworkDefense.Evaluation.Study.Contracts.StudyError
    alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Receipt
    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter
    alias NetworkDefense.Evaluation.Study.Pipeline.Pilot.Collection.IO

    @impl GustAdapter
    def decode(args, _context) do
      with {:ok, value} <- collection_item_id(args),
           {:ok, id} <- Ecto.UUID.cast(value) do
        {:ok, %IO.Item{collection_item_id: id}}
      else
        _invalid -> {:error, StudyError.collection_item_not_found()}
      end
    end

    @impl GustAdapter
    def encode(%IO.Item{receipt: %Receipt{} = receipt}) do
      Receipt.to_params(receipt)
    end

    defp collection_item_id(args) when is_list(args), do: Keyword.fetch(args, :collection_item_id)
  end
end
