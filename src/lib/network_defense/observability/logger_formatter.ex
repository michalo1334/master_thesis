defmodule NetworkDefense.Observability.LoggerFormatter do
  @moduledoc false

  @behaviour LoggerJSON.Formatter

  alias LoggerJSON.Formatters.Basic
  alias NetworkDefense.Observability.LogValue

  @impl true
  def new(opts \\ []), do: {__MODULE__, opts}

  @impl true
  def format(%{msg: {:report, %{label: label, report: report}}, meta: meta} = event, config) do
    if otp_report?(meta) do
      structured_report = label |> format_otp_report(report, meta) |> LogValue.normalize()

      event
      |> Map.put(:msg, {:report, structured_report})
      |> Map.put(:meta, meta |> Map.delete(:report_cb) |> Map.put(:otp_report, structured_report))
      |> Basic.format(config)
    else
      Basic.format(event, config)
    end
  end

  def format(%{msg: {:report, %{label: label} = report}, meta: meta} = event, config) do
    if otp_report?(meta) do
      structured_report = label |> format_otp_report(report, meta) |> LogValue.normalize()

      event
      |> Map.put(:msg, {:report, structured_report})
      |> Map.put(:meta, meta |> Map.delete(:report_cb) |> Map.put(:otp_report, structured_report))
      |> Basic.format(config)
    else
      Basic.format(event, config)
    end
  end

  def format(event, config), do: Basic.format(event, config)

  defp otp_report?(%{domain: [:otp | _]}), do: true
  defp otp_report?(%{domain: [:supervisor_report | _]}), do: true
  defp otp_report?(_meta), do: false

  defp format_otp_report({:gen_server, :terminate}, report, meta) do
    report = Map.delete(report, :elixir_translation)

    %{
      event: "otp.gen_server.terminate",
      process: report_value(report, :name),
      process_label: report_value(report, :process_label),
      last_message: report_value(report, :last_message),
      state: report_value(report, :state),
      client_info: report_value(report, :client_info),
      error: format_error(report_value(report, :reason), Map.get(meta, :crash_reason)),
      report: report
    }
  end

  defp format_otp_report(label, report, meta) do
    report = if is_map(report), do: Map.delete(report, :elixir_translation), else: report

    %{
      event: "otp.report",
      label: label,
      error: format_error(report_value(report, :reason), Map.get(meta, :crash_reason)),
      report: report
    }
  end

  defp format_error(reason, {exception, stacktrace}) when is_exception(exception) do
    %{
      kind: "error",
      type: Atom.to_string(exception.__struct__),
      reason: Exception.message(exception),
      stacktrace: Exception.format_stacktrace(stacktrace),
      original_reason: reason
    }
  end

  defp format_error(reason, {kind, stacktrace})
       when kind in [:throw, :exit] and is_list(stacktrace) do
    %{
      kind: Atom.to_string(kind),
      reason: reason,
      stacktrace: Exception.format_stacktrace(stacktrace)
    }
  end

  defp format_error(reason, _crash_reason), do: %{reason: reason}

  defp report_value(report, key) when is_map(report), do: Map.get(report, key)
  defp report_value(report, key) when is_list(report), do: Keyword.get(report, key)
  defp report_value(_report, _key), do: nil
end
