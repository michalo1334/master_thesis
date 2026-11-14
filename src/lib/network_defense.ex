defmodule NetworkDefense do
  use Boundary, deps: [NetworkDefense.Repo], exports: :all

  @moduledoc """
  NetworkDefense keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc "Checks whether the application database accepts a query."
  @spec database_ready?() :: :ok | {:error, term()}
  def database_ready? do
    case NetworkDefense.Repo.query("SELECT 1") do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
