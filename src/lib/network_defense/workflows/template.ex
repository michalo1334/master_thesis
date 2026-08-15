defmodule NetworkDefense.Workflows.Template do
  @moduledoc false

  @callback steps() :: [String.t()]

  @callback prepare(String.t(), map(), map(), String.t() | nil) ::
              {:ok, String.t()} | {:error, term()}

  @callback run_or_resume(String.t(), map(), map(), String.t()) ::
              {:ok, map()} | {:error, term()}
end
