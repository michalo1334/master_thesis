defmodule NetworkDefense.Evaluation.Family.Client do
  @moduledoc false

  alias NetworkDefense.Evaluation.Family.Contracts.{FamilyError, HolmRequest, HolmResponse}
  alias NetworkDefense.Evaluation.Family.Wire

  # Synchronous, stateless Holm correction call.
  #
  # The client only sends identities and raw p-values. It never sends evidence
  # matrices again.

  @endpoint_path "/v1/families/holm"
  @connect_timeout 2_000
  @receive_timeout 60_000
  @response_limit 65_536
  @documented_error_statuses [400, 413, 415, 422, 500, 503]
  @temporary_error_statuses [500, 503]

  @type classification :: :permanent | :temporary

  @spec holm(HolmRequest.t()) ::
          {:ok, HolmResponse.t()} | {:error, classification(), FamilyError.t()}
  def holm(%HolmRequest{} = request) do
    config = Application.fetch_env!(:network_defense, __MODULE__)

    url =
      config
      |> Keyword.fetch!(:base_url)
      |> URI.merge(@endpoint_path)
      |> URI.to_string()

    options = [
      url: url,
      json: Wire.holm_request(request),
      connect_options: [timeout: Keyword.get(config, :connect_timeout, @connect_timeout)],
      receive_timeout: Keyword.get(config, :receive_timeout, @receive_timeout),
      decode_body: false
    ]

    case Req.post(options) do
      {:ok, %Req.Response{status: 200, body: body}} -> parse_success(body, request)
      {:ok, %Req.Response{status: status, body: body}} -> parse_failure(status, body)
      {:error, _reason} -> {:error, :temporary, FamilyError.unavailable()}
    end
  end

  defp parse_success(body, request) do
    case decode_body(body) do
      {:ok, decoded} ->
        case HolmResponse.parse(decoded, request) do
          {:ok, response} ->
            {:ok, response}

          # Correlation failures carry bounded row diagnostics. A schema
          # failure has no useful rows, so it becomes one generic error.
          {:error, %FamilyError{issues: [_ | _]} = error} ->
            {:error, :permanent, error}

          {:error, _schema_failure} ->
            {:error, :permanent, FamilyError.invalid_response_contract()}
        end

      {:error, _reason} ->
        {:error, :permanent, FamilyError.invalid_response_contract()}
    end
  end

  defp parse_failure(status, body) when status in @documented_error_statuses do
    classification = if status in @temporary_error_statuses, do: :temporary, else: :permanent

    with {:ok, decoded} <- decode_body(body),
         {:ok, error} <- FamilyError.parse_envelope(decoded) do
      {:error, classification, error}
    else
      _error -> {:error, :permanent, FamilyError.invalid_response_contract()}
    end
  end

  defp parse_failure(_status, _body),
    do: {:error, :permanent, FamilyError.invalid_response_contract()}

  defp decode_body(body) when is_binary(body) and byte_size(body) <= @response_limit,
    do: Jason.decode(body)

  defp decode_body(_body), do: {:error, :invalid_body}
end
