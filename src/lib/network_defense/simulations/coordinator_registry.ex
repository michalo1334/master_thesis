defmodule NetworkDefense.Simulations.CoordinatorRegistry do
  @moduledoc """
  Registers local simulation coordinators by experiment ID.
  """

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_init_arg) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}, type: :worker}
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []), do: Registry.start_link(keys: :unique, name: __MODULE__)

  @spec register_current(Ecto.UUID.t()) :: {:ok, pid()} | {:error, term()}
  def register_current(experiment_id), do: Registry.register(__MODULE__, experiment_id, nil)

  @spec cancel(Ecto.UUID.t()) :: :ok
  def cancel(experiment_id) do
    Registry.dispatch(__MODULE__, experiment_id, fn entries ->
      Enum.each(entries, fn {pid, _value} -> send(pid, {:cancel_simulation, experiment_id}) end)
    end)
  end
end
