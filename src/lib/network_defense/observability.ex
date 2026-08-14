defmodule NetworkDefense.Observability do
  @moduledoc false

  require Logger

  alias NetworkDefense.Observability.LogValue

  @ecto_query_event [:network_defense, :repo, :query]
  @live_view_handle_event [:phoenix, :live_view, :handle_event, :start]

  def attach do
    attach_once(:network_defense_ecto_query_log, @ecto_query_event, &handle_telemetry_event/4)

    attach_once(
      :network_defense_live_view_handle_event_log,
      @live_view_handle_event,
      &handle_telemetry_event/4
    )
  end

  def handle_telemetry_event(@ecto_query_event = event, measurements, metadata, _config) do
    log_telemetry(event, measurements, Map.take(metadata, [:query, :repo, :source]))
  end

  def handle_telemetry_event(event, measurements, metadata, _config) do
    log_telemetry(event, measurements, metadata)
  end

  defp log_telemetry(event, measurements, metadata) do
    details =
      %{
        event: Enum.join(event, "."),
        measurements: measurements,
        metadata: metadata
      }
      |> LogValue.normalize()

    Logger.debug("Telemetry event", event: "telemetry.event", telemetry: details)
  end

  defp attach_once(name, event, handler) do
    case :telemetry.attach(name, event, handler, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end
end
