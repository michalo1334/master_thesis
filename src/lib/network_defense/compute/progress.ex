defmodule NetworkDefense.Compute.Progress do
  @moduledoc false

  @spec report((map() -> term()), map()) :: :ok | {:error, term()}
  def report(on_progress, progress) do
    case on_progress.(progress) do
      {:error, _reason} = error -> error
      _result -> :ok
    end
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end
end
