defmodule NetworkDefense.Compute.RabbitMQ.Connection do
  @moduledoc false

  use GenServer

  @reconnect_delay_ms 1_000

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @spec open_channel() :: {:ok, term()} | {:error, :disconnected | term()}
  def open_channel do
    with {:ok, connection} <- GenServer.call(__MODULE__, :connection) do
      AMQP.Channel.open(connection)
    end
  catch
    :exit, _reason -> {:error, :disconnected}
  end

  @impl true
  def init(:ok) do
    send(self(), :connect)
    {:ok, %{connection: nil, monitor: nil}}
  end

  @impl true
  def handle_call(:connection, _from, %{connection: nil} = state) do
    {:reply, {:error, :disconnected}, state}
  end

  def handle_call(:connection, _from, %{connection: connection} = state) do
    {:reply, {:ok, connection}, state}
  end

  @impl true
  def handle_info(:connect, %{connection: nil} = state) do
    case open_connection() do
      {:ok, connection} ->
        {:noreply, %{state | connection: connection, monitor: Process.monitor(connection.pid)}}

      {:error, _reason} ->
        schedule_connect()
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, %{monitor: monitor} = state) do
    schedule_connect()
    {:noreply, %{state | connection: nil, monitor: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp open_connection do
    config =
      :network_defense
      |> Application.fetch_env!(:rabbitmq)
      |> Keyword.take([:host, :port, :virtual_host, :username, :password])

    if is_binary(config[:password]) and byte_size(config[:password]) > 0 do
      AMQP.Connection.open(config)
    else
      {:error, :missing_password}
    end
  rescue
    _error -> {:error, :connection_failed}
  end

  defp schedule_connect, do: Process.send_after(self(), :connect, @reconnect_delay_ms)
end
