defmodule NetworkDefense.Evaluation.Pilot.Client do
  @moduledoc false

  alias NetworkDefense.Evaluation.Pilot.Contracts.{
    CandidateComparisonRequest,
    CandidateComparisonResult,
    PilotError
  }

  alias NetworkDefense.Evaluation.Pilot.Wire

  # Synchronous, stateless candidate comparison call.
  #
  # The client sends one bounded request that contains one comparison matrix
  # and no identity-free row list. It never sends the whole snapshot.

  @endpoint_path "/v1/pilots/candidate-comparisons"
  @connect_timeout 2_000
  @receive_timeout 300_000
  @response_limit 65_536
  @documented_error_statuses [400, 413, 415, 422, 500, 503]
  @temporary_error_statuses [500, 503]

  @type classification :: :permanent | :temporary

  @spec compare(CandidateComparisonRequest.t()) ::
          {:ok, CandidateComparisonResult.t()} | {:error, classification(), PilotError.t()}
  def compare(%CandidateComparisonRequest{} = request) do
    config = Application.fetch_env!(:network_defense, __MODULE__)

    url =
      config
      |> Keyword.fetch!(:base_url)
      |> URI.merge(@endpoint_path)
      |> URI.to_string()

    options = [
      url: url,
      json: Wire.candidate_request(request),
      connect_options: [timeout: Keyword.get(config, :connect_timeout, @connect_timeout)],
      receive_timeout: Keyword.get(config, :receive_timeout, @receive_timeout),
      decode_body: false
    ]

    case Req.post(options) do
      {:ok, %Req.Response{status: 200, body: body}} -> parse_success(body, request)
      {:ok, %Req.Response{status: status, body: body}} -> parse_failure(status, body)
      {:error, _reason} -> {:error, :temporary, PilotError.unavailable()}
    end
  end

  defp parse_success(body, request) do
    case decode_body(body) do
      {:ok, decoded} ->
        case CandidateComparisonResult.parse(decoded, request) do
          {:ok, result} ->
            {:ok, result}

          {:error, %PilotError{issues: [_ | _]} = error} ->
            {:error, :permanent, error}

          {:error, _schema_failure} ->
            {:error, :permanent, PilotError.invalid_response_contract()}
        end

      {:error, _reason} ->
        {:error, :permanent, PilotError.invalid_response_contract()}
    end
  end

  defp parse_failure(status, body) when status in @documented_error_statuses do
    classification = if status in @temporary_error_statuses, do: :temporary, else: :permanent

    with {:ok, decoded} <- decode_body(body),
         {:ok, error} <- PilotError.parse_envelope(decoded) do
      {:error, classification, error}
    else
      _error -> {:error, :permanent, PilotError.invalid_response_contract()}
    end
  end

  defp parse_failure(_status, _body),
    do: {:error, :permanent, PilotError.invalid_response_contract()}

  defp decode_body(body) when is_binary(body) and byte_size(body) <= @response_limit,
    do: Jason.decode(body)

  defp decode_body(_body), do: {:error, :invalid_body}
end
