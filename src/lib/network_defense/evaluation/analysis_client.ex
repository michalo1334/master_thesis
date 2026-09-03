defmodule NetworkDefense.Evaluation.AnalysisClient do
  @moduledoc false

  require Logger
  require OpenTelemetry.Tracer, as: Tracer
  alias NetworkDefense.Observability

  @spec analyze(binary(), String.t(), :pilot | :analyze | String.t()) ::
          {:ok, binary()} | {:error, term()}
  def analyze(archive, run_id, mode)
      when is_binary(archive) and is_binary(run_id) and
             mode in [:pilot, :analyze, "pilot", "analyze"] do
    config = Application.get_env(:network_defense, :analysis_service, [])
    mode = to_string(mode)
    started_at = System.monotonic_time()

    Logger.debug("Evaluation analysis started",
      event: "evaluation.analysis.started",
      run_id: run_id,
      mode: mode,
      input_size_bytes: byte_size(archive)
    )

    Tracer.with_span "evaluation.analysis",
      attributes: %{
        "evaluation.run_id" => run_id,
        "evaluation.analysis.mode" => mode,
        "evaluation.analysis.input_bytes" => byte_size(archive)
      } do
      result =
        with {:ok, url} <- configured_url(config),
             {:ok, response} <- request(url, archive, run_id, mode, config),
             :ok <- validate_status(response.status),
             :ok <- validate_content_type(response.headers) do
          validate_body(response.body, config[:max_zip_bytes])
        end

      status = if match?({:ok, _}, result), do: "completed", else: "failed"

      Logger.log(
        if(status == "completed", do: :debug, else: :error),
        "Evaluation analysis #{status}",
        event: "evaluation.analysis.#{status}",
        run_id: run_id,
        mode: mode,
        input_size_bytes: byte_size(archive),
        output_size_bytes: output_size(result),
        runtime_ms: Observability.duration_ms(started_at),
        error: normalized_error(result)
      )

      Tracer.set_attributes(
        %{
          "evaluation.analysis.status" => status,
          "evaluation.analysis.output_bytes" => output_size(result),
          "error.type" => normalized_error(result)
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
      )

      if status == "completed",
        do: Tracer.set_status(OpenTelemetry.status(:ok)),
        else: Tracer.set_status(OpenTelemetry.status(:error))

      Observability.emit_duration([:network_defense, :evaluation, :analysis], started_at, %{
        run_id: run_id,
        mode: mode,
        status: status,
        error: normalized_error(result)
      })

      result
    end
  end

  def analyze(_archive, _run_id, _mode), do: {:error, :invalid_mode}

  defp configured_url(config) do
    case config[:url] do
      url when is_binary(url) and url != "" -> {:ok, String.trim_trailing(url, "/")}
      _ -> {:error, :not_configured}
    end
  end

  defp request(url, archive, run_id, mode, config) do
    path = if mode == "pilot", do: "/v1/pilot", else: "/v1/analyze"

    request =
      [
        method: :post,
        url: url <> path,
        body: archive,
        headers: [
          {"content-type", "application/zip"},
          {"accept", "application/zip"},
          {"x-correlation-id", run_id}
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
