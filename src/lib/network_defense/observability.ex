defmodule NetworkDefense.Observability do
  @moduledoc false

  require Logger

  alias NetworkDefense.Observability.LogValue

  @ecto_query_event [:network_defense, :repo, :query]
  @live_view_handle_event [:phoenix, :live_view, :handle_event, :start]

  def attach do
    attach_once(:network_defense_ecto_query_log, @ecto_query_event, &handle_ecto_query/4)

    attach_once(
      :network_defense_live_view_handle_event_log,
      @live_view_handle_event,
      &handle_live_view_handle_event/4
    )
  end

  def handle_ecto_query(_event, measurements, metadata, _config) do
    details =
      %{
        event: "ecto.query",
        repository: inspect(metadata.repo),
        query: metadata.query,
        parameters: metadata.params,
        source: metadata.source,
        result: query_result(metadata.result),
        timings_us: timings(measurements)
      }
      |> LogValue.normalize()

    # LoggerJSON emits all metadata; Credo's check only recognizes the legacy console formatter config.
    # credo:disable-for-next-line Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
    Logger.debug("Ecto query", event: "ecto.query", ecto: details)
  end

  def handle_live_view_handle_event(_event, _measurements, metadata, _config) do
    details =
      %{
        event: "live_view.handle_event",
        view: inspect(metadata.socket.view),
        name: metadata.event,
        parameters: Phoenix.Logger.filter_values(metadata.params)
      }
      |> LogValue.normalize()

    # LoggerJSON emits all metadata; Credo's check only recognizes the legacy console formatter config.
    # credo:disable-for-next-line Credo.Check.Warning.MissedMetadataKeyInLoggerConfig
    Logger.debug("LiveView event", event: "live_view.handle_event", live_view: details)
  end

  defp attach_once(name, event, handler) do
    case :telemetry.attach(name, event, handler, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  defp query_result({:ok, _result}), do: "ok"
  defp query_result({:error, _reason}), do: "error"
  defp query_result(result), do: inspect(result)

  defp timings(measurements) do
    Enum.reduce(
      [:idle_time, :queue_time, :query_time, :decode_time, :total_time],
      %{},
      fn measurement, timings ->
        case Map.get(measurements, measurement) do
          time when is_integer(time) ->
            Map.put(
              timings,
              "#{measurement}_us",
              System.convert_time_unit(time, :native, :microsecond)
            )

          _ ->
            timings
        end
      end
    )
  end
end
