defmodule NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.RunSimulation do
  @moduledoc false

  alias NetworkDefense.Evaluation.Study.Contracts.StudyError
  alias NetworkDefense.Evaluation.Study.Pipeline.Collection.{ConcurrencyGate, Receipt, Runner}
  alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO

  # One mapped simulation item.
  #
  # The receipt is the compact result of the stored effect. It carries the
  # identifiers and trial counts that Final analysis and the tier summary read.
  @spec run(IO.Item.t()) :: {:ok, IO.Item.t()} | {:error, StudyError.t()}
  def run(%IO.Item{collection_item_id: collection_item_id} = item) do
    case ConcurrencyGate.run(fn -> Runner.run_simulation_item(collection_item_id) end) do
      {:ok, %Receipt{} = receipt} -> {:ok, %{item | receipt: receipt}}
      {:error, %StudyError{} = error} -> {:error, error}
      _unexpected -> {:error, StudyError.collection_item_not_found()}
    end
  end

  defmodule Gust do
    @moduledoc false

    use NetworkDefense.Evaluation.Study.Pipeline.GustAdapter,
      step: NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.RunSimulation

    alias NetworkDefense.Evaluation.Study.Pipeline.Collection.Receipt
    alias NetworkDefense.Evaluation.Study.Pipeline.Final.Collection.IO
    alias NetworkDefense.Evaluation.Study.Pipeline.GustAdapter

    @impl GustAdapter
    def decode(args, _context) when is_list(args), do: IO.Item.load_from_args(args)

    @impl GustAdapter
    def encode(%IO.Item{receipt: %Receipt{} = receipt}), do: Receipt.to_params(receipt)
  end
end
