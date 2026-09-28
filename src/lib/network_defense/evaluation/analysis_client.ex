defmodule NetworkDefense.Evaluation.AnalysisClient do
  @moduledoc false

  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  alias NetworkDefense.Observability

  @type analysis_mode :: :pilot | :analyze
  @type analysis_status :: :completed | :failed

  @analysis_endpoint "/v1/analyze"
  @study_pilot_endpoint "/v1/study/pilot"
  @study_analysis_endpoint "/v1/study/analyze"

  @spec analyze(binary(), String.t()) :: {:ok, binary()} | {:error, term()}
  def analyze(archive, run_id) when is_binary(archive) and is_binary(run_id) do
    run_lifecycle(archive, run_id, :analyze, analysis_operation())
  end

  @spec analyze_study(binary(), String.t(), analysis_mode()) ::
          {:ok, binary()} | {:error, term()}
  def analyze_study(bundle, study_id, mode)
      when is_binary(bundle) and is_binary(study_id) and mode in [:pilot, :analyze] do
    run_lifecycle(bundle, study_id, mode, study_operation(mode))
  end

  def analyze_study(_bundle, _study_id, _mode), do: {:error, :invalid_mode}

  defp run_lifecycle(archive, identifier, mode, operation) do
    config = Application.get_env(:network_defense, :analysis_service, [])
    started_at = System.monotonic_time()
    identifier_metadata = [{operation.identifier_metadata_key, identifier}]

    Logger.debug(
      "#{operation.log_subject} started",
      [event: "#{operation.event_prefix}.started"] ++
        identifier_metadata ++
        [mode: mode, input_size_bytes: byte_size(archive)]
    )

    Tracer.with_span operation.event_prefix,
      attributes: %{
        operation.identifier_otel_key => identifier,
        "#{operation.event_prefix}.mode" => operation.mode_attribute,
        "#{operation.event_prefix}.input_bytes" => byte_size(archive)
      } do
      result =
        with {:ok, url} <- configured_url(config),
             {:ok, response} <- request(url, archive, identifier, operation.endpoint, config),
             :ok <- validate_status(response.status),
             :ok <- validate_content_type(response.headers) do
          validate_body(response.body, config[:max_zip_bytes])
        end

      status = result_status(result)
      status_text = Atom.to_string(status)
      output_bytes = output_size(result)
      error = normalized_error(result)

      Logger.log(
        log_level(status),
        "#{operation.log_subject} #{status_text}",
        [event: "#{operation.event_prefix}.#{status_text}"] ++
          identifier_metadata ++
          [
            mode: mode,
            status: status,
            input_size_bytes: byte_size(archive),
            output_size_bytes: output_bytes,
            runtime_ms: Observability.duration_ms(started_at),
            error: error
          ]
      )

      Tracer.set_attributes(
        %{
          "#{operation.event_prefix}.status" => status_text,
          "#{operation.event_prefix}.output_bytes" => output_bytes,
          "error.type" => error
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
      )

      Tracer.set_status(trace_status(status))

      Observability.emit_duration(operation.metric_event, started_at, %{
        operation.identifier_metadata_key => identifier,
        mode: mode,
        status: status,
        error: error
      })

      result
    end
  end

  defp configured_url(config) do
    case config[:url] do
      url when is_binary(url) and url != "" -> {:ok, String.trim_trailing(url, "/")}
      _ -> {:error, :not_configured}
    end
  end

  defp request(url, archive, correlation_id, endpoint, config) do
    request =
      [
        method: :post,
        url: url <> endpoint,
        body: archive,
        headers: [
          {"content-type", "application/zip"},
          {"accept", "application/zip"},
          {"x-correlation-id", correlation_id}
        ],
        connect_options: [timeout: config[:connect_timeout_ms]],
        receive_timeout: config[:timeout_ms],
        retry: false
      ]
      |> maybe_put_plug(config[:plug])
      |> Req.new()
      |> OpentelemetryReq.attach(propagate_trace_headers: true)

    case Req.request(request) do
      {:ok, response} -> {:ok, response}
      {:error, _reason} -> {:error, :transport}
    end
  end

  defp analysis_operation do
    %{
      endpoint: @analysis_endpoint,
      event_prefix: "evaluation.analysis",
      metric_event: [:network_defense, :evaluation, :analysis],
      identifier_metadata_key: :run_id,
      identifier_otel_key: "evaluation.run_id",
      log_subject: "Evaluation analysis",
      mode_attribute: "analyze"
    }
  end

  defp study_operation(:pilot) do
    %{
      endpoint: @study_pilot_endpoint,
      event_prefix: "evaluation.study",
      metric_event: [:network_defense, :evaluation, :study],
      identifier_metadata_key: :study_id,
      identifier_otel_key: "evaluation.study_id",
      log_subject: "Evaluation study analysis",
      mode_attribute: "study-pilot"
    }
  end

  defp study_operation(:analyze) do
    %{
      endpoint: @study_analysis_endpoint,
      event_prefix: "evaluation.study",
      metric_event: [:network_defense, :evaluation, :study],
      identifier_metadata_key: :study_id,
      identifier_otel_key: "evaluation.study_id",
      log_subject: "Evaluation study analysis",
      mode_attribute: "study-analyze"
    }
  end

  @spec result_status({:ok, term()} | {:error, term()}) :: analysis_status()
  defp result_status({:ok, _result}), do: :completed
  defp result_status({:error, _reason}), do: :failed

  defp log_level(:completed), do: :debug
  defp log_level(:failed), do: :error

  defp trace_status(:completed), do: OpenTelemetry.status(:ok)
  defp trace_status(:failed), do: OpenTelemetry.status(:error)

  defp maybe_put_plug(options, nil), do: options
  defp maybe_put_plug(options, plug), do: Keyword.put(options, :plug, plug)

  defp validate_status(status) when status in 200..299, do: :ok
  defp validate_status(_status), do: {:error, :http_status}

  defp validate_content_type(headers) do
    content_type = headers |> Map.get("content-type", []) |> List.first()

    if is_binary(content_type) and
         content_type |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase() ==
           "application/zip" do
      :ok
    else
      {:error, :content_type}
    end
  end

  defp validate_body(body, max_bytes) when is_binary(body) and byte_size(body) <= max_bytes,
    do: {:ok, body}

  defp validate_body(body, _max_bytes) when is_binary(body), do: {:error, :response_too_large}
  defp validate_body(_body, _max_bytes), do: {:error, :invalid_body}

  defp output_size({:ok, body}), do: byte_size(body)
  defp output_size(_), do: 0
  defp normalized_error({:ok, _}), do: nil
  defp normalized_error({:error, reason}), do: reason
end
