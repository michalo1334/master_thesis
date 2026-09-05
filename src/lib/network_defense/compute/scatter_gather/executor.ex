defmodule NetworkDefense.Compute.ScatterGather.Executor do
  @moduledoc false

  @callback run(operation :: module(), input :: term(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}
end
