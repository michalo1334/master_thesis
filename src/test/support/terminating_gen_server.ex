defmodule NetworkDefense.TerminatingGenServer do
  @moduledoc false

  use GenServer

  def start_link, do: GenServer.start_link(__MODULE__, :ok)

  @impl true
  def init(:ok), do: {:ok, :ready}

  @impl true
  def handle_cast(:crash, state), do: raise("test GenServer crash from #{inspect(state)}")
end
