defmodule NetworkDefense.Observability.LoggerFormatter do
  @moduledoc false

  @behaviour LoggerJSON.Formatter

  alias LoggerJSON.Formatters.Basic
  alias NetworkDefense.Observability.LogValue

  # LoggerJSON needs these values in their OTP representation while formatting.
  @formatter_metadata_keys [
    :conn,
    :crash_reason,
    :otel_span_id,
    :otel_trace_id,
    :report_cb,
    :time
  ]

  @impl true
  def new(opts \\ []), do: {__MODULE__, opts}

  @impl true
  def format(%{msg: {:report, report}, meta: meta} = event, config) do
    if otp_report?(meta) do
      event
      |> Map.put(:msg, {:string, "OTP report"})
      |> Map.put(
        :meta,
        meta
        |> Map.drop([:crash_reason, :report_cb])
        |> Map.put(:event, "otp.report")
        |> Map.put(:otp_report, normalized_otp_report(report, meta))
        |> normalize_metadata()
      )
      |> Basic.format(config)
    else
      event
      |> Map.put(:meta, normalize_metadata(meta))
      |> Basic.format(config)
    end
  end

  def format(%{meta: meta} = event, config) do
    event
    |> Map.put(:meta, normalize_metadata(meta))
    |> Basic.format(config)
  end

  defp otp_report?(%{domain: [:otp | _]}), do: true
  defp otp_report?(%{domain: [:supervisor_report | _]}), do: true
  defp otp_report?(_meta), do: false

  defp normalized_otp_report(report, meta) do
    %{
      crash_reason: Map.get(meta, :crash_reason),
      report: report
    }
    |> LogValue.normalize()
  end

  defp normalize_metadata(meta) do
    Map.new(meta, fn {key, value} ->
      if key in @formatter_metadata_keys do
        {key, value}
      else
        {key, LogValue.normalize(value)}
      end
    end)
  end
end
