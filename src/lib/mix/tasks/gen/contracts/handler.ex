defmodule Mix.Tasks.Gen.Contracts.Handler do
  @moduledoc false

  @callback render(context :: map()) :: {:emit, String.t()} | :skip
end
