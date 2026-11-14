defmodule Mix.Tasks.Gen.Contracts.Handler do
  use Boundary, classify_to: NetworkDefense.Tooling

  @moduledoc false

  @callback render(context :: map()) :: {:emit, String.t()} | :skip
end
